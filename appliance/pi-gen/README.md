# Raspberry Pi OS Lite + TRS-AI (pi-gen)

This directory holds **TRS-AI-specific** config and a **stage2** overlay for [RPi-Distro/pi-gen](https://github.com/RPi-Distro/pi-gen). It produces a **64-bit Raspberry Pi OS Lite** image (Foundation-supported), **not** the Fedora **AArch64 QEMU UEFI** appliance.

## Pin

The build script checks out pi-gen tag **`TRS_AI_PIGEN_TAG`** (default: `2025-11-24-raspios-bookworm-arm64`). Override when updating:

```bash
export TRS_AI_PIGEN_TAG=2025-11-24-raspios-bookworm-arm64
```

## How to build

From the **repository root** (with `mbasic/` submodule present):

```bash
./appliance/scripts/build-pi-os-image.sh
```

The script clones pi-gen under `${XDG_CACHE_HOME:-~/.cache}/trs-ai-pi-gen/pi-gen`, applies **Lite** skips (stages 3–5), merges this overlay, and runs **`build-docker.sh`** if Docker is available; otherwise it prints how to run **`sudo ./build.sh`** on a Debian-like host with pi-gen dependencies.

## Host dependencies

### Recommended (Fedora / non-Debian): Docker

- **Docker** (or **Podman** with docker CLI compatibility — you may need to adjust `DOCKER=`)
- Network for `docker pull` / `apt` inside the container

pi-gen’s **`build-docker.sh`** runs the full build inside a Debian-based image, avoiding Fedora ↔ Debian package name mismatches.

### Native build (Debian / Ubuntu / Raspberry Pi OS)

Install tools listed in pi-gen’s **`depends`** file (see upstream README), including **qemu-user-static**, **debootstrap**, **parted**, **dosfstools**, etc. On Fedora native builds without Docker, several packages differ or are missing — **prefer Docker**.

### AArch64 user-mode emulation (native x86_64 build only)

Same class as Fedora mkosi **arm64** rootfs: **qemu-user-static** (or **`qemu-user-static-aarch64`**) and **`systemd-binfmt`** / **`binfmt_misc`** so **arm64** chroot binaries execute.

## Output

Images appear under the pi-gen **`deploy/`** directory inside the cached clone, e.g. **`deploy/*.img`** (and **`.zip`** depending on **`DEPLOY_COMPRESSION`** in **`config`**).

## Console (HDMI)

The overlay configures **autologin on tty1** (HDMI / local console) and launches MBASIC via **`trs-ai-basic`**, matching the Fedora x86 appliance (no login password on the console). **Serial** is not the primary documented path.

Stock Pi **login noise** is stripped for an appliance feel: empty **`/etc/issue.d/`** (drops dynamic IP and similar), empty **`/etc/motd`** and **`/etc/update-motd.d`**, Debian **motd-news** disabled, short **`/etc/issue`** / **`issue.net`**, **`~/.hushlogin`**, and removal of **`/etc/profile.d/*.sh`** snippets that print Wi‑Fi/rfkill/country warnings. Wi‑Fi can be configured later (e.g. from a TRS‑AI menu).

## Secrets

Same pattern as **`appliance/scripts/build-image.sh`**: set **`TRS_AI_BUILD_AI_ENV`** to a file, or place **`appliance/secrets/ai.env`**, or the image gets **`appliance/mkosi/build-assets/default-ai.env`**.

## First user / password

**`config`** sets **`DISABLE_FIRST_BOOT_USER_RENAME=1`** and **`FIRST_USER_PASS`** because pi-gen’s **`build.sh`** requires a password when rename is disabled. The TRS-AI stage then runs **`passwd -d`** on **`FIRST_USER_NAME`** so the **local console user has no password**, like the Fedora appliance (autologin only; no prompt).

If **`ENABLE_SSH=1`**, use **`PUBKEY_SSH_FIRST_USER`** (pi-gen) or harden SSH yourself — an empty password on the console user is normal for a kiosk-style appliance but is risky if SSH password auth is exposed.
