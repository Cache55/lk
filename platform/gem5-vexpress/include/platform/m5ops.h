/*
 * Copyright (c) 2026 Cache55
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
#pragma once

#include <stdint.h>

/* gem5 pseudo instructions (gem5 include/gem5/asm/generic/m5ops.h) */
void m5_exit(uint64_t ns_delay);
void m5_fail(uint64_t ns_delay, uint64_t code);
void m5_dump_stats(uint64_t ns_delay, uint64_t ns_period);
void m5_reset_stats(uint64_t ns_delay, uint64_t ns_period);
