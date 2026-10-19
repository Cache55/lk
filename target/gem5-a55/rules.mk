LOCAL_DIR := $(GET_LOCAL_DIR)

GLOBAL_INCLUDES += \
    $(LOCAL_DIR)/include

PLATFORM := gem5-vexpress

# 8 x Cortex-A55 in AArch32, Thumb-2 kernel. ARM_CPU picks the FPU variant:
# cortex-a55 (FP + SIMD, softfp), cortex-a55-nosimd (FP, softfp),
# cortex-a55-nofp (soft float), cortex-a55-nofp-nosimd-softfp
# (+nofp+nosimd, softfp ABI).
ARCH := arm
ARM_CPU ?= cortex-a55
WITH_SMP := 1
SMP_MAX_CPUS := 8
ENABLE_THUMB := true
