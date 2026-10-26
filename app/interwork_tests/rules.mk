LOCAL_DIR := $(GET_LOCAL_DIR)

MODULE := $(LOCAL_DIR)

# ARM <-> Thumb interworking tests (A/R profile cores, which have both
# instruction sets). Registers "ut interwork_tests" and the "interwork" command.
ifeq ($(ARCH),arm)
ifneq ($(SUBARCH),arm-m)
MODULE_SRCS += \
	$(LOCAL_DIR)/interwork.S \
	$(LOCAL_DIR)/interwork_tests.c
endif
endif

MODULE_DEPS += \
	lib/unittest

include make/module.mk
