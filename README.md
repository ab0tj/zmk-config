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

Both default to `SNIPPET=studio-rpc-usb-uart` (ZMK Studio's USB endpoint, as in
`build.yaml`); override it with `SNIPPET=other` or disable it with `make SNIPPET=`.

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
| [dabao](https://github.com/justinmklam/dabao) | `west build -b nice_nano -S studio-rpc-usb-uart -- -DSHIELD=dabao -DZMK_EXTRA_MODULES=/abs/path/to/kb_zmk_ps2_mouse_trackpoint_driver/` |

The `-S studio-rpc-usb-uart` snippet supplies ZMK Studio's USB CDC-ACM endpoint
and builds every behavior so it can be assigned from Studio. `CONFIG_ZMK_STUDIO=y`
itself comes from `boards/shields/dabao/dabao.conf`, so it applies to CI and
local builds alike. Zephyr refuses to apply a snippet to an existing build
directory, so run `west build -p` (or `make pristine`) after changing it.

## ZMK Studio

Every build is Studio-capable: it exposes a physical layout (`dabao-layouts.dtsi`),
eight named layers (`Default`, `Symbols`, `Nav`, `Misc`, `Mouse`, `Scroll` plus two
empty reserved layers), and all ZMK behaviors, so bindings and layers can be
changed at runtime instead of reflashing.

1. Flash the firmware as usual (see below) and plug the keyboard in over USB.
2. Open <https://zmk.studio> in Chrome/Edge, or install the native app from
   <https://zmk.studio/download> and connect. On Linux, USB access may require
   membership of the `dialout` or `uucp` group.
3. Unlock the keyboard: hold the right-thumb `ENTER` (position 33, `&lt 3`) and
   tap the rightmost right-thumb key (position 35, `&key_repeat` on the default
   layer) to fire `&studio_unlock`. The device relocks on disconnect.

No `&out` binding is defined, so the endpoint is chosen automatically: USB
whenever it is connected, otherwise BLE. USB is therefore the simplest way to
reach Studio, and it is also the only endpoint the Chrome/Edge web app supports.

Note that Studio stores the keymap on the keyboard. **After the first save from
Studio, edits to `dabao.keymap` no longer take effect** until you use Studio's
"Restore Stock Settings" — that reverts the device to the keymap committed here.
The one deliberate loss when using the `Misc` layer is `&key_repeat` at position
35, which is now the unlock key; the default layer keeps it everywhere else.

## Flashing Firmware

For the nice!nano, simply double tap the reset button to put it into bootloader mode, then copy the .uf2 file from the build directory to the mounted drive.

```sh
# Docker build output
cp ./build/dabao-nice_nano-zmk.uf2 /media/$USER/NICENANO/

# Native toolchain build output
cp ~/zmk/app/build/zephyr/zmk.uf2 /media/$USER/NICENANO/
```
