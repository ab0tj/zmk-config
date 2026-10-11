# zmk-config

This repository contains configuration, custom shield files, and keymaps for all my keyboards.

## Building via Github Actions

Firmware is built via Github Actions, and can be downloaded via the artifacts. This avoids needing to set up a local toolchain.

## Building Locally (Docker)

No local toolchain required. `bin/build.sh` runs the same steps as the GitHub
Actions workflow inside the official ZMK toolchain container
(`zmkfirmware/zmk-build-arm:stable`), which is the same image the reusable
`build-user-config.yml` workflow uses:

```bash
bin/build.sh          # nice_nano + dabao, as configured in build.yaml
bin/build.sh -p       # pristine (clean) build
```

Override the target for other boards/shields, e.g.:

```bash
BOARD=nice_nano SHIELD=dabao bin/build.sh
```

A thin Makefile wrapper is also available: `make`, `make pristine` (clean
build), `make SHIELD=other BOARD=other`, `make clean`.

Firmware is written to `./build/<artifact-name>.uf2`. The first run clones
`zmk`, Zephyr and the modules into `~/.cache/zmk-build` (a few GB); later
builds reuse that workspace and only rebuild what changed.

## Building Locally (Native Toolchain)

Alternatively, to build without Docker you'll need to set up the ZMK
development environment. Follow the [ZMK Setup Guide](https://zmk.dev/docs/development/local-toolchain/setup/native) to get started.

```bash
source ~/zephyrproject/.venv/bin/activate
cd ~/zmk/app
```

Once you have the environment set up, set this `zmk-config` repo as a permanent CMake argument with:

```bash
west config build.cmake-args -- -DZMK_CONFIG=/abs/path/to/zmk-config
```

Now you can build the firmware for a specific keyboard by running:

```bash
# Optionally, use `west build -p ...` for pristine/clean builds
west build -b <board> -d build/<board> -- -DSHIELD=<shield>
```

Replace `<board>` with the name of the board (e.g., `nice_nano`) and `<shield>` with the name of the shield (e.g., `dabao`). The table below shows specific build commands for each keyboard in this repo:

| Board/Shield | Command |
|--------------|---------|
| [dabao](https://github.com/justinmklam/dabao) | `west build -b nice_nano -- -DSHIELD=dabao -DZMK_EXTRA_MODULES=/abs/path/to/kb_zmk_ps2_mouse_trackpoint_driver/` |

## Flashing Firmware

For the nice!nano, simply double tap the reset button to put it into bootloader mode, then copy the .uf2 file from the build directory to the mounted drive.

```sh
# Docker build output
cp ./build/dabao-nice_nano-zmk.uf2 /media/$USER/NICENANO/

# Native toolchain build output
cp ~/zmk/app/build/zephyr/zmk.uf2 /media/$USER/NICENANO/
```
