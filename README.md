# zmk-config

This repository contains configuration, custom shield files, and keymaps for all my keyboards.

## Controller layout: `nosd` or `sd`

Firmware is not portable across nRF52840 controllers with different bootloaders.
A bootloader only runs an application linked at the offset it expects, so each
controller belongs to one of two flash layouts, and this repo builds both:

| Layout | Application offset | Bootloader | Snippets |
|--------|--------------------|------------|----------|
| `nosd` | `0x1000` | no SoftDevice | `nrf52840-nosd studio-rpc-usb-uart` |
| `sd` | `0x26000` | SoftDevice reserved | `studio-rpc-usb-uart` |

`nosd` is the default here because that is what the official nice!nano v2 uses:
ZMK's stock `nice_nano` board definition links the application at `0x26000`
(the SoftDevice layout, correct for nice!nano v1 and most pro micro clones), and
a `nosd` bootloader never looks there. The flash itself still succeeds - it just
lands where nothing ever boots it.

Check a controller by putting it in its bootloader (double tap reset) and reading
what it reports:

```sh
cat /run/media/$USER/NICENANO/INFO_UF2.TXT
```

```text
SoftDevice: not found            # nosd - use LAYOUT=nosd
SoftDevice: S140 version 6.1.1   # sd   - use LAYOUT=sd
```

`Board-ID: nRF52840-nicenano` vs `...-nicenano-v2` distinguishes the controller
revision, but the `SoftDevice:` line is what decides the layout.

Same check for a `.uf2` you already have, without a controller:

```sh
# prints the application offset it was linked for (00001000 or 00026000)
od -An -tx4 -j 12 -N 4 build/dabao-nice_nano-nosd.uf2
```

Flashing the wrong layout looks like a broken flash: the copy appears to work and
the drive unmounts, but the controller stays in its bootloader with the blue LED
blinking and never shows up as a keyboard (no `1d50` USB device).

**Back up before switching layouts.** Firmware built with `nrf52840-nosd`
overwrites the SoftDevice region, and a controller whose bootloader depends on a
SoftDevice can need a bootloader reflash afterwards. The bootloader exposes the
controller's current flash contents as `CURRENT.UF2` on the mounted drive:

```sh
cp /run/media/$USER/NICENANO/CURRENT.UF2 ~/Downloads/nicenano-backup-$(date +%F).uf2
```

Copying that file back to the `NICENANO` drive restores the previous contents.

## Building via Github Actions

Firmware is built via Github Actions, and can be downloaded via the artifacts. This avoids needing to set up a local toolchain.

`build.yaml` builds one artifact per layout, named as the local builds are:
`dabao-nice_nano-nosd` and `dabao-nice_nano-sd`.

## Building Locally (Docker)

No local toolchain required. `bin/build.sh` runs the same steps as the GitHub
Actions workflow inside the official ZMK toolchain container
(`zmkfirmware/zmk-build-arm:stable`), which is the same image the reusable
`build-user-config.yml` workflow uses:

```bash
bin/build.sh          # nice_nano + dabao, nosd layout
bin/build.sh -p       # pristine (clean) build
LAYOUT=sd bin/build.sh
```

Override the target for other boards/shields, e.g.:

```bash
BOARD=nice_nano SHIELD=dabao bin/build.sh
```

A thin Makefile wrapper is also available:

```bash
make                  # default layout (LAYOUT=nosd)
make LAYOUT=sd        # SoftDevice layout
make nosd             # shorthand for the two layouts
make sd
make both             # both firmwares in one go
make pristine         # clean build for the selected layout
make pristine-sd      # clean build for one layout (also pristine-nosd)
make SHIELD=other BOARD=other
make clean            # drop build/<artifact>.uf2 for the selected layout
make distclean        # also drop the cached west workspace
```

The layout is the only difference between the two firmwares, and it is part of the
build directory and artifact name, so `make both` needs no pristine rebuild in
between.

Snippets come from the layout (`nosd`: `nrf52840-nosd studio-rpc-usb-uart`, `sd`:
`studio-rpc-usb-uart`); override them with `SNIPPET=other` or disable them with
`make SNIPPET=`. Note that Zephyr *ignores* a snippet change in an existing build
directory, so use `make pristine` (or `west build -p`) after changing snippets.

Firmware is written to `./build/<artifact>.uf2`, e.g.
`./build/dabao-nice_nano-nosd.uf2`. The first run clones `zmk`, Zephyr and the
modules into `~/.cache/zmk-build` (a few GB); later builds reuse that workspace
and only rebuild what changed.

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
west build -b <board> -d build/<board>-<layout> -S <snippets> -- -DSHIELD=<shield>
```

Replace `<board>` with the name of the board (e.g., `nice_nano`) and `<shield>` with the name of the shield (e.g., `dabao`). The table below shows specific build commands for each keyboard in this repo, once per layout:

| Board/Shield | Layout | Command |
|--------------|--------|---------|
| [dabao](https://github.com/justinmklam/dabao) | `nosd` | `west build -b nice_nano -S nrf52840-nosd -S studio-rpc-usb-uart -- -DSHIELD=dabao -DZMK_EXTRA_MODULES=/abs/path/to/kb_zmk_ps2_mouse_trackpoint_driver/` |
| [dabao](https://github.com/justinmklam/dabao) | `sd` | `west build -b nice_nano -S studio-rpc-usb-uart -- -DSHIELD=dabao -DZMK_EXTRA_MODULES=/abs/path/to/kb_zmk_ps2_mouse_trackpoint_driver/` |

`-S` may be repeated, or given one space separated value (`-S "nrf52840-nosd
studio-rpc-usb-uart"`); ZMK's CI workflow passes a single quoted value. The
`studio-rpc-usb-uart` snippet supplies ZMK Studio's USB CDC-ACM endpoint and
builds every behavior so it can be assigned from Studio. `CONFIG_ZMK_STUDIO=y`
itself comes from `boards/shields/dabao/dabao.conf`, so it applies to CI and
local builds alike.

## ZMK Studio

Every build is Studio-capable: it exposes a physical layout (`dabao-layouts.dtsi`),
nine layers (`Default`, `Symbols`, `Nav`, `Misc`, `Mouse`, `Boost`, `Slow` plus
two empty reserved layers), and all ZMK behaviors, so bindings and layers can
be changed at runtime instead of reflashing.

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
# Docker / Makefile build output, e.g. the nosd layout
cp ./build/dabao-nice_nano-nosd.uf2 /run/media/$USER/NICENANO/

# Native toolchain build output (see -d above)
cp ~/zmk/app/build/nice_nano-nosd/zephyr/zmk.uf2 /run/media/$USER/NICENANO/
```

GitHub Actions artifacts use the same names per layout:
`dabao-nice_nano-nosd.uf2` and `dabao-nice_nano-sd.uf2`.

Copy the firmware built for the layout your controller uses (see
[Controller layout](#controller-layout-nosd-or-sd)). The drive disappearing while
the copy is still flushing is normal, as is a file manager error: the bootloader
reboots as soon as it has received the last block.

A successful flash takes the controller out of the bootloader, so the blue LED
stops blinking and the keyboard shows up as a USB device:

```sh
lsusb | grep -i 1d50              # ZMK Project: the firmware is running
journalctl -kf | grep -E 'usb|hid'
```

If the drive unmounts, the LED keeps blinking and no such device appears, the
firmware was linked for the wrong layout (or the controller needs its bootloader
reflashed).
