/*
 * Copyright (c) 2025 Travis Geiselbrecht
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
#pragma once

#include <arch/arm64.h>
#include <arch/defines.h>
#include <arch/ops.h>
#include <lk/compiler.h>
#include <stdint.h>
#include <sys/types.h>

__BEGIN_CDECLS

void arm64_mp_init(void);

// Tell the ARM64 code how many secondary cpus to expect, which
// will cause it to allocate percpu structures for them.
void arm64_set_secondary_cpu_count(int count);

// Platforms that reset every cpu at the kernel entry (ARM64_SECONDARIES_SPIN_AT_RESET):
// let the secondaries waiting in arm64_reset continue. Call after
// arm64_set_secondary_cpu_count() and lk_init_secondary_cpus().
void arm64_release_secondaries_from_reset(void);

struct arm64_percpu {
    uint cpu_num;
    uint64_t mpidr;
} __CPU_ALIGN;

static inline void arm64_set_percpu(struct arm64_percpu *pc) {
    __asm__ volatile("mov x18, %0" ::"r"(pc));
}

static inline struct arm64_percpu *arm64_get_percpu(void) {
    struct arm64_percpu *pc;
    __asm__ volatile("mov %0, x18" : "=r"(pc));
    return pc;
}

static inline uint arch_curr_cpu_num(void) {
    const struct arm64_percpu *pc = arm64_get_percpu();
    return pc->cpu_num;
}

// Translate a CPU number back to the MPIDR of the CPU.
uint64_t arm64_cpu_num_to_mpidr(uint cpu_num);

__END_CDECLS
