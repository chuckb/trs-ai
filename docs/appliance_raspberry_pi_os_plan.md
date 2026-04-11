# Raspberry Pi OS Lite + TRS-AI (Pi 500 / Pi family)

**Supported path for Raspberry Pi hardware** (e.g. **Pi 500**): **Raspberry Pi OS Lite** (64-bit), produced with **[pi-gen](https://github.com/RPi-Distro/pi-gen)** plus the overlay in [`appliance/pi-gen/`](../appliance/pi-gen/).

This is **not** the Fedora **`build-image.sh --arch aarch64`** image (that artifact is **QEMU UEFI only** — see [appliance_aarch64_rpi_uefi_plan.md](appliance_aarch64_rpi_uefi_plan.md)).

## Console: HDMI + keyboard

The image targets **headless use on an HDMI monitor** with a **keyboard**: autologin on **tty1** runs MBASIC. **Serial** is optional for debugging, not the primary documented experience.

## Build

From the repo root (with **`mbasic/`** submodule):

```bash
./appliance/scripts/build-pi-os-image.sh
```

- Clones pi-gen under **`~/.cache/trs-ai-pi-gen/pi-gen`** (override with **`TRS_AI_PIGEN_DIR`**).
- Pins tag **`TRS_AI_PIGEN_TAG`** (default in script; see [`appliance/pi-gen/README.md`](../appliance/pi-gen/README.md)).
- Applies **Lite** skips (no desktop stages).
- Prefers **Docker** via **`build-docker.sh`** so Fedora hosts do not need every Debian package name.

**`--native`**: `sudo ./build.sh` inside the pi-gen tree (Debian-like host with pi-gen `depends` satisfied).

## AI / secrets

Same idea as the Fedora appliance: **`TRS_AI_BUILD_AI_ENV`**, or **`appliance/secrets/ai.env`**, or the default fixture env from **`appliance/mkosi/build-assets/default-ai.env`**.

## First user / password

**`config`** sets **`FIRST_USER_PASS`** only to satisfy pi-gen when **`DISABLE_FIRST_BOOT_USER_RENAME=1`**. The overlay clears the console user’s password with **`passwd -d`** so boot matches the Fedora appliance (**autologin, no password prompt** on HDMI/tty1). Harden SSH separately if enabled.

## Flash to SD / USB

Use the **`.img`** from pi-gen **`deploy/`** (exact name includes date — `ls deploy/` after a build).

```bash
./appliance/scripts/flash-appliance-sd.sh /path/to/deploy/*.img /dev/mmcblk0
```

## Host dependencies

See [`appliance/pi-gen/README.md`](../appliance/pi-gen/README.md): **Docker** recommended on Fedora; otherwise native pi-gen **`depends`** on Debian/Ubuntu/Raspberry Pi OS.

## References

- [plan_raspberry_pi_os_pivot.md](plan_raspberry_pi_os_pivot.md) — agreed direction and doc policy.
- [valtzu/rpi-mkosi](https://github.com/valtzu/rpi-mkosi) — optional mkosi/repart ideas only; this repo uses **Foundation OS + pi-gen** for Pi hardware.
