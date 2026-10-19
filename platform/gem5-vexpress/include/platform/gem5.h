/*
 * Copyright (c) 2026 Cache55
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
#pragma once

/*
 * gem5 VExpress_GEM5_V1 machine (src/dev/arm/RealView.py), as configured by
 * gem5 with a GICv2:
 *
 *   0x1C09_0000  PL011 UART0, SPI 37
 *   0x2C00_1000  GICv2 distributor
 *   0x2C00_2000  GICv2 cpu interface
 *   0x8000_0000  DRAM
 *
 * Generic timer PPIs: 27 virtual EL1, 30 physical EL1, 29 physical EL3.
 */

/* memory: phys == virt, so no trampoline is needed when the mmu comes on */
#define MEMORY_BASE_PHYS     (MEMBASE)
#define MEMORY_APERTURE_SIZE (MEMSIZE)

/* the motherboard and on chip peripherals, 0x1C00_0000 - 0x2FFF_FFFF */
#define PERIPHERAL_BASE_PHYS (0x1C000000UL)
#define PERIPHERAL_BASE_SIZE (0x14000000UL)
#define PERIPHERAL_BASE_VIRT (0xE0000000UL)
#define PERIPHERAL_VIRT(pa)  (PERIPHERAL_BASE_VIRT + ((pa) - PERIPHERAL_BASE_PHYS))

#define UART0_BASE_PHYS      (0x1C090000UL)
#define UART0_BASE           PERIPHERAL_VIRT(UART0_BASE_PHYS)
#define UART0_INT            (37)

#define GICD_BASE_PHYS       (0x2C001000UL)
/*
 * A GICv2 distributor is 4KB, but the arm_gic driver maps at least
 * GICD_MIN_SIZE (64KB, the GICv3 frame). The extra is only mapped, never
 * accessed, so it is harmless that it spans the cpu interface.
 */
#define GICD_SIZE            (0x10000UL)
#define GICC_BASE_PHYS       (0x2C002000UL)
#define GICC_SIZE            (0x2000UL)

#define ARM_GENERIC_TIMER_VIRTUAL_INT  (27)
#define ARM_GENERIC_TIMER_PHYSICAL_INT (30)

/* the gic driver's interrupt table size: SGIs, PPIs and the SPIs we use */
#define MAX_INT              (128)
