# LK test build for gem5: 8 x Cortex-A55 (AArch32), ARM_CPU=cortex-a55-nofp-nosimd-softfp:
# -mcpu=cortex-a55+nofp+nosimd -mfloat-abi=softfp.
#   make TOOLCHAIN=atfe ATFE_ROOT=<ATfE install> gem5-a55-nofp-nosimd-softfp-test
ARM_CPU := cortex-a55-nofp-nosimd-softfp

include project/gem5-a55-test.mk
