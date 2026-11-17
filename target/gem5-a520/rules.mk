LOCAL_DIR := $(GET_LOCAL_DIR)

GLOBAL_INCLUDES += \
    $(LOCAL_DIR)/include

PLATFORM := gem5-vexpress

# 8 x Cortex-A520 in AArch64 on gem5's VExpress_GEM5_V1 (configs/lk_a520.py).
ARCH := arm64
ARM_CPU := cortex-a520
WITH_SMP := 1
SMP_MAX_CPUS := 8

# ATfE's AArch64 bare metal multilibs (lib/clang-runtimes/aarch64-none-elf)
# are selected by this triple; LK's arm64 default is aarch64-elf.
CLANG_ARCH_TRIPLE := aarch64-none-elf

# arch/arm64 turns ARM_CPU into a define only, so pass -mcpu here.
# +nosve: LK does not yet enable SVE (CPACR_EL1.ZEN, ZCR_EL1) or save the SVE
# predicate registers, and clang would otherwise auto-vectorise float code
# with SVE instructions that trap.
ARCH_arm64_COMPILEFLAGS += -mcpu=cortex-a520+nosve
