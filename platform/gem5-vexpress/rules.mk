LOCAL_DIR := $(GET_LOCAL_DIR)

MODULE := $(LOCAL_DIR)

# gem5's VExpress_GEM5_V1 machine with a GICv2, run bare metal. The target
# picks the architecture:
#   ARCH=arm    AArch32 (gem5 highest_el_is_64 = False), e.g. Cortex-A55
#   ARCH=arm64  AArch64 (gem5 highest_el_is_64 = True), e.g. Cortex-A520
ARCH ?= arm
ifeq ($(ARCH),arm64)
ARM_CPU ?= cortex-a520
# gem5 resets every cpu at the kernel entry and has no PSCI firmware: the
# secondaries wait in start.S until platform_init() releases them.
GLOBAL_DEFINES += ARM64_SECONDARIES_SPIN_AT_RESET=1
else
ARM_CPU ?= cortex-a55
endif
WITH_SMP ?= 1
SMP_MAX_CPUS ?= 8

LK_HEAP_IMPLEMENTATION ?= dlmalloc

MODULE_SRCS += \
    $(LOCAL_DIR)/debug.c \
    $(LOCAL_DIR)/m5ops.S \
    $(LOCAL_DIR)/platform.c

# gem5 puts DRAM at 0x8000_0000. AArch32: LK links the kernel at that same
# address, so physical and virtual match. AArch64: the kernel runs at
# KERNEL_BASE (0xffff000000000000) and its ELF load addresses are physical.
MEMBASE := 0x80000000
MEMSIZE ?= 0x10000000   # 256MB, keep in step with gem5's --mem-size
KERNEL_LOAD_OFFSET := 0

MODULE_DEPS += \
    dev/interrupt/arm_gic \
    dev/timer/arm_generic \
    dev/uart/pl011 \
    lib/cbuf

GLOBAL_DEFINES += \
    MEMBASE=$(MEMBASE) \
    MEMSIZE=$(MEMSIZE) \
    PLATFORM_SUPPORTS_PANIC_SHELL=1 \
    CONSOLE_HAS_INPUT_BUFFER=1 \
    TIMER_ARM_GENERIC_SELECTED=CNTV

LINKER_SCRIPT += \
    $(BUILDDIR)/system-onesegment.ld

include make/module.mk
