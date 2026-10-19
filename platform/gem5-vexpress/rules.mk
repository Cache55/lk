LOCAL_DIR := $(GET_LOCAL_DIR)

MODULE := $(LOCAL_DIR)

# gem5's VExpress_GEM5_V1 machine with a GICv2, run as a bare metal AArch32
# system (gem5's highest_el_is_64 = False).
ARCH := arm
ARM_CPU ?= cortex-a55
WITH_SMP ?= 1
SMP_MAX_CPUS ?= 8

LK_HEAP_IMPLEMENTATION ?= dlmalloc

MODULE_SRCS += \
    $(LOCAL_DIR)/debug.c \
    $(LOCAL_DIR)/m5ops.S \
    $(LOCAL_DIR)/platform.c

# gem5 puts DRAM at 0x8000_0000, the same address LK links the kernel at, so
# physical and virtual addresses of the kernel match.
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
