/*
 * Copyright (c) 2026 Cache55
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */

/*
 * ARM <-> Thumb interworking tests: run every call site generated in
 * interwork.S (see there for the instructions, alignments and IRQ points).
 *
 *   ut interwork_tests
 *     interwork_all_sites       every site once
 *     interwork_irq_points      every site with an IRQ pending: sites with
 *                               an IRQ point must take it exactly there
 *     interwork_cold_sites      every site after invalidating the I-cache and
 *                               TLB, so straddling calls miss between halves
 *     interwork_cold_irq_points both
 *     interwork_page_tlb        page-straddling calls copied into 4KB pages,
 *                               so the second half needs its own page walk
 *     interwork_under_irqs      every site on all cpus while cpu 0 sends them
 *                               reschedule IPIs and a 1ms timer runs
 *   interwork [passes] [us]  the stress for longer (default 200 passes, an
 *                            IPI every 20us), alternating plain and IRQ
 *                            point passes
 *   interwork list           print every site
 */
#include <arch/atomic.h>
#include <arch/mp.h>
#include <arch/ops.h>
#include <kernel/mp.h>
#include <kernel/thread.h>
#include <kernel/timer.h>
#include <kernel/vm.h>
#include <lk/compiler.h>
#include <lib/unittest.h>
#include <lk/console_cmd.h>
#include <lk/debug.h>
#include <lk/err.h>
#include <platform.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define IW_F_IRQ 1      /* run with an IRQ pending, the site must take it */

struct iw_site {
    uint32_t (*fn)(uint32_t);
    const char *name;
    uint32_t flags;
};

extern const struct iw_site iw_table_start[];
extern const struct iw_site iw_table_end[];

#define IW_SEED   0x1000u
/* the callee adds 1, the site 0x40 */
#define IW_RESULT (IW_SEED + 0x41u)

struct iw_result {
    uint bad;           /* wrong return value */
    uint irq_sites;     /* sites with an IRQ point, run with an IRQ pending */
    uint irq_taken;     /* ...that took the IRQ inside the site */
    uint not_pending;   /* the SGI never showed up as pending */
};

static size_t iw_count(void) {
    return (size_t)(iw_table_end - iw_table_start);
}

/* how a pass runs each site */
#define IW_MODE_IRQ  1  /* with a reschedule SGI pending: taken at the IRQ point */
#define IW_MODE_COLD 2  /* after invalidating the I-cache and the TLB, so every
                         * fetch misses, also between the halves of a call */

/* the AArch32 Interrupt Status Register: bit 7 = an IRQ is pending */
static inline uint32_t iw_read_isr(void) {
    uint32_t isr;
    __asm__ volatile("mrc p15, 0, %0, c12, c1, 0" : "=r"(isr));
    return isr;
}

/* ICIALLU and TLBIALL on this cpu: the next fetches miss and walk again */
static inline void iw_cold_fetch(void) {
    __asm__ volatile(
        "mcr p15, 0, %0, c7, c5, 0\n"   /* ICIALLU: invalidate the I-cache */
        "mcr p15, 0, %0, c8, c7, 0\n"   /* TLBIALL: invalidate the TLB */
        "dsb\n"
        "isb\n"
        :: "r"(0) : "memory");
}

/*
 * Run one site with IRQs masked and a reschedule SGI pending on this cpu, so
 * its first "cpsie i" takes the IRQ at the instruction after it. Returns the
 * site's result; *taken says whether the IRQ came in before the site returned.
 */
static uint32_t iw_call_with_irq(uint32_t (*fn)(uint32_t), bool cold, bool *taken,
                                 bool *pending) {
    arch_disable_ints();
    uint cpu = arch_curr_cpu_num();
    ulong before = thread_stats[cpu].reschedule_ipis;

    arch_mp_send_ipi(1u << cpu, MP_IPI_RESCHEDULE);
    /* wait for the GIC to deliver it, so it is pending at the first cpsie */
    *pending = false;
    for (uint spin = 0; spin < 100000; spin++) {
        if (iw_read_isr() & (1u << 7)) {
            *pending = true;
            break;
        }
    }

    if (cold)
        iw_cold_fetch();
    uint32_t r = fn(IW_SEED);

    *taken = thread_stats[cpu].reschedule_ipis != before;
    arch_enable_ints();     /* a site without an IRQ point takes it here */
    return r;
}

/* one call in the given mode */
static uint32_t iw_call(uint32_t (*fn)(uint32_t), uint mode, bool *taken, bool *pending) {
    if (mode & IW_MODE_IRQ)
        return iw_call_with_irq(fn, mode & IW_MODE_COLD, taken, pending);
    if (mode & IW_MODE_COLD)
        iw_cold_fetch();
    return fn(IW_SEED);
}

/* every site once, in the given mode */
static void iw_pass(uint mode, bool report, struct iw_result *res) {
    bool irq_mode = mode & IW_MODE_IRQ;
    for (const struct iw_site *s = iw_table_start; s < iw_table_end; s++) {
        bool taken = false, pending = true;
        uint32_t r = iw_call(s->fn, mode, &taken, &pending);

        if (r != IW_RESULT) {
            res->bad++;
            if (report)
                printf("interwork: cpu %u site '%s' (%p)%s%s returned %#x, expected %#x\n",
                       arch_curr_cpu_num(), s->name, s->fn, irq_mode ? " with IRQ" : "",
                       (mode & IW_MODE_COLD) ? " cold" : "", r, IW_RESULT);
        }
        if (irq_mode && !pending)
            res->not_pending++;
        if (irq_mode && (s->flags & IW_F_IRQ)) {
            res->irq_sites++;
            if (taken)
                res->irq_taken++;
            else if (report && pending)
                printf("interwork: site '%s' did not take its IRQ inside\n", s->name);
        }
    }
}

/* ------------------------------------------------------------- stress */

struct iw_stress {
    volatile int running;           /* workers still going */
    volatile int failures;
    volatile int ticks;             /* timer interrupts seen */
    uint passes;
};

static enum handler_return iw_tick(struct timer *t, lk_time_t now, void *arg) {
    struct iw_stress *st = arg;
    atomic_add(&st->ticks, 1);
    return INT_NO_RESCHEDULE;
}

static int iw_worker(void *arg) {
    struct iw_stress *st = arg;
    for (uint i = 0; i < st->passes; i++) {
        struct iw_result res = { 0 };
        /* cycle plain, IRQ point, cold, cold + IRQ point passes */
        iw_pass(i & (IW_MODE_IRQ | IW_MODE_COLD), true, &res);
        if (res.bad)
            atomic_add(&st->failures, (int)res.bad);
    }
    atomic_add(&st->running, -1);
    return 0;
}

/* microseconds between the caller's reschedule IPIs to the workers: dense
 * enough to land in every kind of code, sparse enough that a cycle level
 * simulator's workers still spend most of their time in the sites */
#define IW_IPI_PERIOD_US 20

/*
 * One worker per active cpu other than the caller's, pinned there, each
 * running every site st->passes times. The caller sends reschedule IPIs to the
 * others every ipi_us until they finish, and a 1ms periodic timer runs too.
 * Returns the number of failed calls; *ipis and *ticks report the interrupts.
 */
static int iw_stress_run(uint passes, uint ipi_us, uint *ipis_out, int *ticks_out,
                         uint *workers_out) {
    struct iw_stress st = { .passes = passes };
    thread_t *workers[SMP_MAX_CPUS] = { 0 };
    uint self = arch_curr_cpu_num();
    mp_cpu_mask_t active = mp_get_active_mask();
    uint nworkers = 0;
    uint ipis = 0;

    timer_t tick;
    timer_initialize(&tick);
    timer_set_periodic(&tick, 1, iw_tick, &st);

    /* with a single cpu the caller is the worker and there are no IPIs */
    if ((active & ~(1u << self)) == 0) {
        st.running = 1;
        iw_worker(&st);
    } else {
        for (uint cpu = 0; cpu < SMP_MAX_CPUS; cpu++) {
            if (cpu == self || !(active & (1u << cpu)))
                continue;
            thread_t *t = thread_create("interwork", iw_worker, &st, DEFAULT_PRIORITY,
                                        DEFAULT_STACK_SIZE);
            if (!t)
                continue;
            thread_set_pinned_cpu(t, (int)cpu);
            workers[cpu] = t;
            atomic_add(&st.running, 1);
            nworkers++;
            thread_resume(t);
        }
        while (st.running > 0) {
            mp_reschedule(MP_IPI_TARGET_ALL_BUT_LOCAL, 0, 0);
            ipis++;
            lk_bigtime_t next = current_time_hires() + ipi_us;
            while (current_time_hires() < next && st.running > 0)
                ;
        }
        for (uint cpu = 0; cpu < SMP_MAX_CPUS; cpu++) {
            if (workers[cpu])
                thread_join(workers[cpu], NULL, INFINITE_TIME);
        }
    }

    timer_cancel(&tick);
    if (ipis_out)
        *ipis_out = ipis;
    if (ticks_out)
        *ticks_out = st.ticks;
    if (workers_out)
        *workers_out = nworkers;
    return st.failures;
}

/* ---------------------------------------------------------- unit tests */

static bool iw_check_pass(uint mode) {
    BEGIN_TEST;
    struct iw_result res = { 0 };
    ASSERT_TRUE(iw_count() > 0, "no interworking sites");
    iw_pass(mode, true, &res);
    if (mode & IW_MODE_IRQ)
        unittest_printf("\n        %zu sites, %u with an IRQ point, %u took it inside ",
                        iw_count(), res.irq_sites, res.irq_taken);
    EXPECT_EQ(0u, res.bad, "sites returned a wrong result");
    if (mode & IW_MODE_IRQ) {
        EXPECT_EQ(0u, res.not_pending, "the self SGI did not become pending");
        EXPECT_EQ(res.irq_sites, res.irq_taken, "sites that did not take their IRQ");
        EXPECT_TRUE(res.irq_sites > 0, "no sites with an IRQ point");
    }
    END_TEST;
}

static bool interwork_all_sites(void) { return iw_check_pass(0); }
static bool interwork_irq_points(void) { return iw_check_pass(IW_MODE_IRQ); }
static bool interwork_cold_sites(void) { return iw_check_pass(IW_MODE_COLD); }
static bool interwork_cold_irq_points(void) { return iw_check_pass(IW_MODE_COLD | IW_MODE_IRQ); }

/* the relocatable blob of page-straddling calls (interwork.S) */
extern const char iw_blob_start[], iw_blob_end[];
extern uint32_t iw_blob_bl(uint32_t), iw_blob_blx(uint32_t);
extern uint32_t iw_blob_bl_ic(uint32_t), iw_blob_blx_ic(uint32_t);
extern uint32_t iw_blob_bl_ir(uint32_t), iw_blob_blx_ir(uint32_t);

/*
 * Copy the blob into a new mapping of 4KB pages, so the second half of each
 * straddling call needs its own TLB entry, and run every entry with a cold
 * I-cache and TLB, plainly and with an IRQ pending, many times.
 */
static bool interwork_page_tlb(void) {
    BEGIN_TEST;
    static const struct {
        uint32_t (*fn)(uint32_t);
        const char *name;
        bool irq_point;
    } entries[] = {
        { iw_blob_bl,     "bl page-straddle",         false },
        { iw_blob_blx,    "blx page-straddle",        false },
        { iw_blob_bl_ic,  "bl page-straddle, IRQ at the call",  true },
        { iw_blob_blx_ic, "blx page-straddle, IRQ at the call", true },
        { iw_blob_bl_ir,  "bl page-straddle, IRQ at the return",  true },
        { iw_blob_blx_ir, "blx page-straddle, IRQ at the return", true },
    };
    size_t size = (size_t)(iw_blob_end - iw_blob_start);
    void *mem = NULL;

    /* written by the copy, then run */
    status_t err = vmm_alloc(vmm_get_kernel_aspace(), "interwork", ROUNDUP(size, PAGE_SIZE),
                             &mem, PAGE_SIZE_SHIFT, 0,
                             ARCH_MMU_FLAG_PERM_READ | ARCH_MMU_FLAG_PERM_WRITE |
                             ARCH_MMU_FLAG_PERM_EXECUTE);
    if (err != NO_ERROR)
        printf("interwork: vmm_alloc of %zu bytes failed: %d\n", size, err);
    ASSERT_EQ(NO_ERROR, err, "vmm_alloc");
    memcpy(mem, iw_blob_start, size);
    arch_sync_cache_range((addr_t)mem, size);

    uint taken_count = 0, irq_runs = 0;
    for (uint iter = 0; iter < 16; iter++) {
        for (size_t i = 0; i < countof(entries); i++) {
            /* the same entry in the copy: keep the Thumb bit of the pointer */
            uintptr_t off = (uintptr_t)entries[i].fn - (uintptr_t)iw_blob_start;
            uint32_t (*fn)(uint32_t) = (uint32_t (*)(uint32_t))((uintptr_t)mem + off);
            for (uint mode = IW_MODE_COLD; mode <= (IW_MODE_COLD | IW_MODE_IRQ); mode++) {
                bool taken = false, pending = true;
                uint32_t r = iw_call(fn, mode, &taken, &pending);
                if (r != IW_RESULT)
                    printf("interwork: %s (%p)%s returned %#x\n", entries[i].name, fn,
                           (mode & IW_MODE_IRQ) ? " with IRQ" : "", r);
                EXPECT_EQ(IW_RESULT, r, entries[i].name);
                if ((mode & IW_MODE_IRQ) && entries[i].irq_point) {
                    irq_runs++;
                    taken_count += taken ? 1 : 0;
                }
            }
        }
    }
    unittest_printf("\n        %zu byte blob at %p (4KB pages), %u IRQ point runs, %u taken inside ",
                    size, mem, irq_runs, taken_count);
    EXPECT_EQ(irq_runs, taken_count, "IRQ points not taken inside");

    vmm_free_region(vmm_get_kernel_aspace(), (vaddr_t)mem);
    END_TEST;
}

static bool interwork_under_irqs(void) {
    BEGIN_TEST;
    uint ipis = 0, workers = 0;
    int ticks = 0;
    int failures = iw_stress_run(4, IW_IPI_PERIOD_US, &ipis, &ticks, &workers);
    unittest_printf("\n        %zu sites x 4 passes on %u cpus, %u IPIs, %d timer ticks ",
                    iw_count(), workers ? workers : 1, ipis, ticks);
    EXPECT_EQ(0, failures, "calls returned a wrong result under interrupts");
    END_TEST;
}

BEGIN_TEST_CASE(interwork_tests)
RUN_TEST(interwork_all_sites);
RUN_TEST(interwork_irq_points);
RUN_TEST(interwork_cold_sites);
RUN_TEST(interwork_cold_irq_points);
RUN_TEST(interwork_page_tlb);
RUN_TEST(interwork_under_irqs);
END_TEST_CASE(interwork_tests)

/* -------------------------------------------------------------- command */

static int cmd_interwork(int argc, const console_cmd_args *argv) {
    if (argc >= 2 && !strcmp(argv[1].str, "list")) {
        uint irq = 0;
        for (const struct iw_site *s = iw_table_start; s < iw_table_end; s++) {
            printf("%p %s%s\n", s->fn, s->name, (s->flags & IW_F_IRQ) ? " [irq]" : "");
            irq += (s->flags & IW_F_IRQ) ? 1 : 0;
        }
        printf("%zu sites, %u with an IRQ point\n", iw_count(), irq);
        return 0;
    }

    uint passes = (argc >= 2) ? (uint)argv[1].u : 200;
    uint ipi_us = (argc >= 3) ? (uint)argv[2].u : IW_IPI_PERIOD_US;
    uint ipis = 0, workers = 0;
    int ticks = 0;

    printf("interwork: %zu sites, %u passes per cpu, an IPI every %u us\n", iw_count(),
           passes, ipi_us);
    lk_bigtime_t start = current_time_hires();
    int failures = iw_stress_run(passes, ipi_us, &ipis, &ticks, &workers);
    lk_bigtime_t took = current_time_hires() - start;

    printf("interwork: %s: %d failed calls, %llu calls on %u cpus, %u IPIs, %d timer ticks, %llu us\n",
           failures ? "FAILED" : "PASSED", failures,
           (unsigned long long)iw_count() * passes * (workers ? workers : 1),
           workers ? workers : 1, ipis, ticks, (unsigned long long)took);
    return failures ? ERR_GENERIC : 0;
}

STATIC_COMMAND_START
STATIC_COMMAND("interwork", "ARM/Thumb interworking stress: [passes] [ipi_us] | list", &cmd_interwork)
STATIC_COMMAND_END(interwork_tests);
