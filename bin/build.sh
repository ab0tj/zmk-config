#!/usr/bin/env bash
#
# Build ZMK firmware locally without installing the Zephyr toolchain.
#
# This replicates what .github/workflows/build.yml does in CI by running the
# same steps (west init -> west update -> west build) inside the official
# toolchain image, zmkfirmware/zmk-build-arm:stable.
#
# Usage:
#   bin/build.sh               # nice_nano + dabao (the build.yaml defaults)
#   bin/build.sh -p            # pristine / clean build
#   BOARD=... SHIELD=... bin/build.sh
#   SNIPPET= bin/build.sh      # build without the studio-rpc-usb-uart snippet
#   ZMK_IMAGE=zmkfirmware/zmk-build-arm:4.1-branch bin/build.sh
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
WORKSPACE="${ZMK_WORKSPACE:-$HOME/.cache/zmk-build}"
OUT_DIR="${OUT_DIR:-$REPO_DIR/build}"
HOST_UID="$(id -u):$(id -g)"

# Same artifact naming as the reusable CI workflow.
BUILD_NAME="${SHIELD:+${SHIELD}-}${BOARD}"
ARTIFACT="${ARTIFACT_NAME:-${BUILD_NAME}-zmk}"

PRISTINE=""
case "${1:-}" in
  -p | --pristine) PRISTINE="-p" ;;
esac

# ZMK Studio talks over a USB CDC-ACM serial port, which the shield's
# CONFIG_ZMK_STUDIO=y alone does not provide. The snippet also defines
# ZMK_BEHAVIORS_KEEP_ALL so every behavior is available to assign in Studio.
SNIPPET="${SNIPPET-studio-rpc-usb-uart}"

mkdir -p "$WORKSPACE" "$OUT_DIR"

echo "==> image:     $IMAGE"
echo "==> board:     $BOARD"
echo "==> shield:    ${SHIELD:-<none>}"
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
