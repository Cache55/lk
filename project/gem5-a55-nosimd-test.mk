# LK test build for gem5: 8 x Cortex-A55 (AArch32), ARM_CPU=cortex-a55-nosimd.
#   make TOOLCHAIN=atfe ATFE_ROOT=<ATfE install> gem5-a55-nosimd-test
ARM_CPU := cortex-a55-nosimd

include project/gem5-a55-test.mk
