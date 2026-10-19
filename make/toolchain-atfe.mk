# Arm Toolchain for Embedded (ATfE) support.
#
# ATfE is an LLVM based bare metal toolchain from Arm
# (https://github.com/arm/arm-toolchain). Build with it by passing
# TOOLCHAIN=atfe and, unless its clang is first on the PATH, ATFE_ROOT:
#
#   make TOOLCHAIN=atfe ATFE_ROOT=/path/to/ATfE-23.1.0-Linux-x86_64 <project>
#
# This selects LK's clang path (TOOLCHAIN=clang) with every tool taken from
# ATfE's bin directory: clang, ld.lld and the llvm binutils. libgcc is replaced
# by ATfE's compiler-rt builtins for the selected multilib, which engine.mk
# finds through clang -print-libgcc-file-name.

ifeq ($(TOOLCHAIN),atfe)

ifndef ATFE_ROOT
ATFE_ROOT := $(patsubst %/bin/clang,%,$(realpath $(shell which clang 2>/dev/null)))
endif
ifeq ($(wildcard $(ATFE_ROOT)/bin/clang),)
$(error TOOLCHAIN=atfe: no clang under ATFE_ROOT='$(ATFE_ROOT)'; set ATFE_ROOT to the ATfE install directory)
endif
ifeq ($(wildcard $(ATFE_ROOT)/lib/clang-runtimes/multilib.yaml),)
$(error TOOLCHAIN=atfe: '$(ATFE_ROOT)' does not look like an ATfE install (no lib/clang-runtimes/multilib.yaml))
endif

override TOOLCHAIN := clang
CLANG_BINDIR := $(ATFE_ROOT)/bin
# ATfE ships ld.lld; ask for it by name so engine.mk resolves it from CLANG_BINDIR.
LD := ld.lld

ATFE_VERSION := $(shell $(CLANG_BINDIR)/clang --version | sed -n '1s/.*version \([0-9.]*\).*/\1/p')
$(info ATFE_ROOT = $(ATFE_ROOT) (clang $(ATFE_VERSION)))

endif
