# Convenience wrapper around bin/build.sh (which runs the ZMK toolchain container).
#
#   make                 # build nice_nano + dabao, default LAYOUT
#   make LAYOUT=sd       # build for a SoftDevice (0x26000) controller
#   make nosd / make sd  # shorthand for the two layouts
#   make both            # build both layouts (two firmware files)
#   make pristine        # clean build for the selected LAYOUT
#   make pristine-sd     # clean build for one layout (also pristine-nosd)
#   make SHIELD=other    # override the target
#   make SNIPPET=        # build without any snippets
#   make clean           # drop the firmware output for the selected LAYOUT
#   make distclean       # also drop the cached west workspace
#
# LAYOUT is the controller flash layout and the only thing that differs between
# the two firmware files; @see bin/build.sh for what each one means and how to
# tell which layout a controller needs. Both variants keep separate build
# directories, so switching between them needs no pristine rebuild.
#
# Defaults mirror build.yaml, which remains the source of truth for CI.

SHELL := /bin/bash
.DEFAULT_GOAL := build

BOARD ?= nice_nano
SHIELD ?= dabao

LAYOUT ?= nosd

ZMK_IMAGE ?= zmkfirmware/zmk-build-arm:stable
ZMK_WORKSPACE ?= $(HOME)/.cache/zmk-build

# LAYOUT is part of the name, so both variants can coexist in build/ and in the
# cached workspace's build directories. Matches the CI artifact names.
BUILD_NAME := $(if $(SHIELD),$(SHIELD)-)$(BOARD)-$(LAYOUT)

# Forward SNIPPET only when the caller set it: undefined lets bin/build.sh pick
# the layout's snippets, while SNIPPET= explicitly means "no snippets".
SNIPPET_ENV := $(if $(filter undefined,$(origin SNIPPET)),,SNIPPET="$(SNIPPET)")

# Quote the values that may hold space separated lists.
ZMK_ENV := BOARD=$(BOARD) SHIELD="$(SHIELD)" LAYOUT="$(LAYOUT)" $(SNIPPET_ENV) \
	ZMK_IMAGE=$(ZMK_IMAGE) ZMK_WORKSPACE=$(ZMK_WORKSPACE) \
	BUILD_NAME="$(BUILD_NAME)"

.PHONY: build pristine clean distclean nosd sd both pristine-nosd pristine-sd

build:
	$(ZMK_ENV) bin/build.sh

pristine:
	$(ZMK_ENV) bin/build.sh -p

# Build one layout, whichever is not the default.
nosd sd:
	$(MAKE) LAYOUT=$@ build

pristine-nosd pristine-sd:
	$(MAKE) LAYOUT=$(patsubst pristine-%,%,$@) pristine

# Both variants, each in its own build directory.
both:
	$(MAKE) LAYOUT=nosd build
	$(MAKE) LAYOUT=sd build

# Remove the firmware output for BOARD/SHIELD/LAYOUT.
clean:
	rm -rf build/$(BUILD_NAME)

# Also drop the cached west workspace (multi-GB, re-cloned on the next build).
distclean:
	rm -rf build $(ZMK_WORKSPACE)
