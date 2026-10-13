# Convenience wrapper around bin/build.sh (which runs the ZMK toolchain container).
#
#   make                 # build nice_nano + dabao
#   make pristine        # clean build
#   make SHIELD=other    # override the target
#   make SNIPPET=        # build without the studio-rpc-usb-uart snippet
#
# Defaults mirror build.yaml, which remains the source of truth for CI.

SHELL := /bin/bash
.DEFAULT_GOAL := build

BOARD ?= nice_nano
SHIELD ?= dabao

# ZMK Studio needs the USB CDC-ACM endpoint from this Zephyr snippet (see build.yaml).
SNIPPET ?= studio-rpc-usb-uart

ZMK_IMAGE ?= zmkfirmware/zmk-build-arm:stable
ZMK_WORKSPACE ?= $(HOME)/.cache/zmk-build

BUILD_NAME := $(if $(SHIELD),$(SHIELD)-)$(BOARD)

ZMK_ENV := BOARD=$(BOARD) SHIELD=$(SHIELD) SNIPPET=$(SNIPPET) ZMK_IMAGE=$(ZMK_IMAGE) ZMK_WORKSPACE=$(ZMK_WORKSPACE)

.PHONY: build pristine clean distclean

build:
	$(ZMK_ENV) bin/build.sh

pristine:
	$(ZMK_ENV) bin/build.sh -p

# Remove the firmware output for BOARD/SHIELD.
clean:
	rm -rf build/$(BUILD_NAME)

# Also drop the cached west workspace (multi-GB, re-cloned on the next build).
distclean:
	rm -rf build $(ZMK_WORKSPACE)
