#!/usr/bin/env bash
#
# Build ZMK firmware locally without installing the Zephyr toolchain.
#
# This replicates what .github/workflows/build.yml does in CI by running the
# same steps (west init -> west update -> west build) inside the official
# toolchain image, zmkfirmware/zmk-build-arm:stable.
#
# Usage:
#   bin/build.sh               # nice_nano + dabao, nosd layout (see LAYOUT)
#   bin/build.sh -p            # pristine / clean build
#   BOARD=... SHIELD=... bin/build.sh
#   LAYOUT=sd bin/build.sh     # SoftDevice layout instead of nosd
#   SNIPPET= bin/build.sh      # build with no snippets at all
#   ZMK_IMAGE=zmkfirmware/zmk-build-arm:4.1-branch bin/build.sh
#
# LAYOUT selects the controller flash layout: where the bootloader expects the
# application, and therefore which snippets supply it. The two are mutually
# incompatible - firmware linked for one layout does not run on a controller
# whose bootloader uses the other.
#
#   nosd - no SoftDevice. Application at 0x1000, snippets
#          "nrf52840-nosd studio-rpc-usb-uart". Official nice!nano v2 boards;
#          INFO_UF2.TXT reports "SoftDevice: not found".
#   sd   - SoftDevice reserved. Application at 0x26000, snippet
#          "studio-rpc-usb-uart". nice!nano v1 and most pro micro clones;
#          INFO_UF2.TXT reports "SoftDevice: S140 ...".
#
# Check a controller with: cat /run/media/$USER/NICENANO/INFO_UF2.TXT
#
# LAYOUT is part of BUILD_NAME, so each layout builds into its own directory in
# the workspace and switching layouts never needs a pristine rebuild.
#
# The west workspace (zmk, zephyr, modules) is cached in ZMK_WORKSPACE
# (default ~/.cache/zmk-build), so only the first run pays the clone cost.
# Firmware lands in ./build/. The repo itself is mounted read-write, exactly
# as CI does, but ZMK does not modify it.
#
# The container runs as your own uid with a throwaway HOME, so everything it
# writes (cache, build dir, firmware) is owned by you rather than root.

set -euo pipefail

# Lives in bin/, so the repo root is one level up.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE="${ZMK_IMAGE:-zmkfirmware/zmk-build-arm:stable}"
BOARD="${BOARD:-nice_nano}"
SHIELD="${SHIELD:-dabao}"

# Snippet sets per layout; SNIPPET (if set, even empty) overrides them.
LAYOUT="${LAYOUT:-nosd}"
case "$LAYOUT" in
  nosd) layout_snippets="nrf52840-nosd studio-rpc-usb-uart" ;;
  sd) layout_snippets="studio-rpc-usb-uart" ;;
  *)
    echo "unknown LAYOUT '$LAYOUT': expected 'nosd' or 'sd'" >&2
    exit 2
    ;;
esac

WORKSPACE="${ZMK_WORKSPACE:-$HOME/.cache/zmk-build}"
OUT_DIR="${OUT_DIR:-$REPO_DIR/build}"
HOST_UID="$(id -u):$(id -g)"

# Same artifact naming as the reusable CI workflow, plus the layout so the two
# variants never collide. Both are overridable by the caller (the Makefile).
BUILD_NAME="${BUILD_NAME:-${SHIELD:+${SHIELD}-}${BOARD}-${LAYOUT}}"
ARTIFACT="${ARTIFACT_NAME:-${BUILD_NAME}}"

PRISTINE=""
case "${1:-}" in
  -p | --pristine) PRISTINE="-p" ;;
esac

# The layout decision belongs to the controller, not the keyboard - see the
# LAYOUT descriptions above. SNIPPET is only defaulted when unset, so an empty
# SNIPPET= still means "build with no snippets".
SNIPPET="${SNIPPET-$layout_snippets}"

mkdir -p "$WORKSPACE" "$OUT_DIR"

echo "==> image:     $IMAGE"
echo "==> board:     $BOARD"
echo "==> shield:    ${SHIELD:-<none>}"
echo "==> layout:    $LAYOUT"
echo "==> snippet:   ${SNIPPET:-<none>}"
echo "==> workspace: $WORKSPACE"
echo "==> output:    $OUT_DIR/$ARTIFACT.uf2"

# Older versions of this script ran the container as root, leaving the cached
# workspace root-owned. Fix that once, from a throwaway root container, so this
# build and `make distclean` can work as your own user.
if [ -d "$WORKSPACE" ] &&
  [ -n "$(find "$WORKSPACE" -maxdepth 1 -mindepth 1 -not -user "$(id -u)" -print -quit)" ]; then
  echo "==> fixing cache ownership (one-time: legacy root-owned workspace)"
  docker run --rm --user 0:0 -e HOME=/tmp -e HOST_UID="$HOST_UID" \
    -v "$WORKSPACE":/workspace \
    "$IMAGE" \
    bash -c 'chown -R "$HOST_UID" /workspace'
fi

docker run --rm \
  --user "$HOST_UID" \
  -e HOME=/tmp \
  -v "$REPO_DIR":/config-src \
  -v "$WORKSPACE":/workspace \
  -v "$OUT_DIR":/out \
  -e BOARD="$BOARD" \
  -e SHIELD="$SHIELD" \
  -e SNIPPET="$SNIPPET" \
  -e BUILD_NAME="$BUILD_NAME" \
  -e ARTIFACT="$ARTIFACT" \
  -e PRISTINE="$PRISTINE" \
  -w /workspace \
  "$IMAGE" \
  bash -c '
set -euo pipefail

# The config repo has to sit at <workspace>/config for west init -l to find
# it, and this repo is loaded as an extra module so that boards/shields/dabao
# (and its keymap) is discoverable.
mkdir -p /workspace/config
cp -R /config-src/config/. /workspace/config/

if [ ! -d /workspace/.west ]; then
  echo "==> west init (first run: clones zmk, zephyr and modules)"
  west init -l /workspace/config
fi

echo "==> west update"
west update --fetch-opt=--filter=tree:0
west zephyr-export

BUILD_DIR="/workspace/build/${BUILD_NAME}"

echo "==> west build -b ${BOARD}${SHIELD:+ -DSHIELD=${SHIELD}}${SNIPPET:+ -S ${SNIPPET}}"
west build -s zmk/app -d "$BUILD_DIR" -b "$BOARD" ${PRISTINE} ${SNIPPET:+-S "$SNIPPET"} -- \
  -DZMK_CONFIG=/workspace/config \
  -DZMK_EXTRA_MODULES=/config-src \
  ${SHIELD:+-DSHIELD="$SHIELD"}

for ext in uf2 bin hex; do
  if [ -f "$BUILD_DIR/zephyr/zmk.$ext" ]; then
    cp "$BUILD_DIR/zephyr/zmk.$ext" "/out/${ARTIFACT}.$ext"
    echo "==> wrote /out/${ARTIFACT}.$ext"
    break
  fi
done
'
