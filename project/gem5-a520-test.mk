# LK test build for gem5: 8 x Cortex-A520 (AArch64), built with ATfE.
#   make TOOLCHAIN=atfe ATFE_ROOT=<ATfE install> gem5-a520-test
# Run it with configs/lk_a520.py. The AArch32 Cortex-A55 builds
# (gem5-a55-*-test, configs/lk_a55.py) are unchanged.
TARGET := gem5-a520

include project/virtual/test.mk
