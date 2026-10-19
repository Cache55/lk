/*
 * Copyright (c) 2026 Cache55
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
#include <lk/asm.h>

/*
 * gem5 pseudo instructions. gem5 decodes them from an A32 coprocessor
 * encoding (util/m5/src/abi/arm/m5op.S), so these stay in ARM state even when
 * the rest of the kernel is built as Thumb; callers reach them through
 * interworking branches. Arguments follow the AAPCS: 64 bit values in r0:r1,
 * r2:r3.
 */
#define M5OP_EXIT        0x21
#define M5OP_FAIL        0x22
#define M5OP_RESET_STATS 0x40
#define M5OP_DUMP_STATS  0x41

.text
.arm

.macro m5op name, func
FUNCTION(\name)
    .long 0xEE000110 | (\func << 16)
    bx      lr
.endm

m5op m5_exit, M5OP_EXIT
m5op m5_fail, M5OP_FAIL
m5op m5_reset_stats, M5OP_RESET_STATS
m5op m5_dump_stats, M5OP_DUMP_STATS
