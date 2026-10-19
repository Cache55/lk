/*
 * Copyright (c) 2026 Cache55
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
#include <platform/gem5.h>
#include <platform/m5ops.h>

#include <arch.h>
#include <lk/debug.h>
#include <lk/trace.h>
#include <lk/init.h>
#include <dev/interrupt/arm_gic.h>
#include <dev/timer/arm_generic.h>
#include <dev/uart/pl011.h>
#include <kernel/vm.h>
#include <platform.h>

#define LOCAL_TRACE 0

/* initial memory mappings. parsed by start.S */
struct mmu_initial_mapping mmu_initial_mappings[] = {
    /* all of memory */
    {
        .phys = MEMORY_BASE_PHYS,
        .virt = KERNEL_BASE,
        .size = MEMORY_APERTURE_SIZE,
        .flags = 0,
        .name = "memory"
    },

    /* the motherboard and on chip peripherals */
    {
        .phys = PERIPHERAL_BASE_PHYS,
        .virt = PERIPHERAL_BASE_VIRT,
        .size = PERIPHERAL_BASE_SIZE,
        .flags = MMU_INITIAL_MAPPING_FLAG_DEVICE,
        .name = "peripherals"
    },

    /* null entry to terminate the list */
    { 0 }
};

static pmm_arena_t ram_arena = {
    .name = "ram",
    .base = MEMORY_BASE_PHYS,
    .size = MEMORY_APERTURE_SIZE,
    .flags = PMM_ARENA_FLAG_KMAP,
};

void platform_early_init(void) {
    const struct pl011_config uart_config = {
        .base = UART0_BASE,
        .irq = UART0_INT,
        .flag = PL011_FLAG_DEBUG_UART,
    };
    pl011_init_early(0, &uart_config);

    /*
     * The virtual timer reads the same counter in either security state, so it
     * works whether gem5 leaves us in secure or non secure SVC.
     */
    arm_generic_timer_init(ARM_GENERIC_TIMER_VIRTUAL_INT, 0);

    pmm_add_arena(&ram_arena);
}

static void platform_postvm_init(uint level) {
    const struct arm_gic_init_info gic_info = {
        .gic_revision = 2,
        .gicd_paddr = GICD_BASE_PHYS,
        .gicd_size = GICD_SIZE,
        .gicc_paddr = GICC_BASE_PHYS,
        .gicc_size = GICC_SIZE,
    };
    arm_gic_init_map(&gic_info);
}

LK_INIT_HOOK(platform_postvm_init, platform_postvm_init, LK_INIT_LEVEL_VM);

void platform_init(void) {
    pl011_init(0);

    /*
     * Every cpu starts at the kernel entry under gem5 (no boot loader). The
     * secondaries park in start.S until arch_init releases arm_boot_cpu_lock.
     */
    dprintf(INFO, "gem5: %d cpus configured\n", SMP_MAX_CPUS);
}

static void gem5_shutdown(void) {
    /* ends the simulation; gem5 reports the exit cause */
    m5_exit(0);
}

void platform_halt(platform_halt_action suggested_action, platform_halt_reason reason) {
    platform_halt_default(suggested_action, reason, &gem5_shutdown, &gem5_shutdown);
}
