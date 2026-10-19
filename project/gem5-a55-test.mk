# LK test build for gem5: 8 x Cortex-A55 (AArch32), built with ATfE.
#   make TOOLCHAIN=atfe ATFE_ROOT=<ATfE install> gem5-a55-test
TARGET := gem5-a55

include project/virtual/test.mk
