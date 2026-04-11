# Plan: Raspberry Pi OS deployment (Pi 500) without breaking Fedora appliances

**Status:** implemented in-tree (bootlab removed, pi-gen overlay + `build-pi-os-image.sh`, docs deconflicted). Treat this file as historical rationale.

## Context and constraints

- **Fedora mkosi** under `appliance/mkosi/` stays the **Milestone 1 appliance** for **x86_64** and for the **`aarch64` / `arm64`** mkosi profile. That profile exists for **QEMU `virt` + AAVMF (UEFI)** and other **generic AArch64 UEFI** bring-up — **it is not** the Raspberry Pi shipping image and **must not** be documented as “the AArch64 Pi image.”
- **Pi 500 / Raspberry Pi deployment** uses **Raspberry Pi OS Lite** (Foundation-supported), built via **pi-gen** (recommended first), with **native VideoCore boot** on the boot FAT — not the Fedora+ESP+systemd-boot chain.
- **[valtzu/rpi-mkosi](https://github.com/valtzu/rpi-mkosi)** remains an interesting reference (mkosi layout, repart, postoutput) only; OS choice stays Foundation-aligned unless a later optional track says otherwise.

## Documentation policy (per project agreement)

### 1) UEFI on Pi hardware — do not document as a goal

- **Remove** from project docs the narrative that the project is pursuing **Pi 5 / Pi 500 boot via UEFI** or step-by-step “get Pi booting UEFI” guidance.
- **Replace** with a short, factual statement, e.g.: **At the time of this project, Pi 500 booting via UEFI was not a supported or validated path** (and Fedora’s lagging Pi 500 support reinforced dropping that track). **QEMU AArch64 UEFI** remains documented only as **emulation** of a **generic** UEFI disk, not as Pi firmware behavior.

### 2) Delineate AArch64 vs Raspberry Pi

- **Naming:** In README, architecture docs, and flash scripts, prefer explicit phrases:
  - **“Fedora AArch64 (QEMU UEFI)”** or **`build-image.sh --arch aarch64`** → artifact for **AAVMF / virt**, **not** SD card for Pi.
  - **“Raspberry Pi OS (pi-gen)”** or **`build-pi-os-image.sh`** → artifact for **Pi 500 / Pi family**.
- **Avoid** phrases that imply **aarch64 defaults to Raspberry Pi** (e.g. “flash the aarch64 image to the Pi” without naming which pipeline).
- **Optional hardening:** Comment banners in `appliance/mkosi/mkosi.profiles/aarch64/mkosi.conf` and `flash-appliance-sd.sh` that state **QEMU-only** unless the user explicitly passes a Pi OS `.img` path.

### 3) Console: HDMI headless, not serial-first

- **Target experience:** **Headless boot on an HDMI monitor** — user sees **MBASIC / TRS-AI on the framebuffer/HDMI console**, with **keyboard** (and optionally mouse only if needed later). **Serial console is not** the primary documented path for Pi deployment.
- **Implementation note:** When porting `mkosi.postinst.chroot` logic into pi-gen stages, prioritize **getty on the virtual console / tty1** (and ensure **`config.txt` / cmdline** do not force serial-only or disable HDMI). Treat **serial** (UART) as **optional debugging**.
- **Doc edits:** Replace plan/checklist language that says “serial boot” or “serial console” as the main Pi bring-up with **HDMI + keyboard**.

## Phase 1 — Repo hygiene (no risk to Fedora builds)

1. **Bootlab** — Remove or archive `appliance/bootlab-uefi-hello/`; grep and fix references.
2. **Docs** — Apply **§ Documentation policy** above:
  - Rework `docs/appliance_aarch64_rpi_uefi_plan.md`: strip Pi UEFI how-to; state **Pi 500 UEFI not supported at project time**; retitle or split so **Fedora AArch64 = QEMU UEFI only** is obvious; **HDMI** as console where Pi is mentioned historically.
  - Add `docs/appliance_raspberry_pi_os_plan.md` for pi-gen / Pi OS Lite / HDMI-focused bring-up.
3. **Flash script / README** — Deconflict artifacts: default Pi instructions → pi-gen output; Fedora `.raw` AArch64 → **QEMU or explicit advanced use**, never implied Pi default.

## Phase 2 — Raspberry Pi OS Lite + TRS-AI (pi-gen)

1. `**appliance/pi-gen/`** — Pinned `RPi-Distro/pi-gen`, Lite **64-bit** config, custom stage(s) for `mbasic`, `ai.env`, user/getty/**HDMI console**, systemd/network parity with Fedora appliance where sensible.
2. `**appliance/scripts/build-pi-os-image.sh`** — Invokes pi-gen; documents **Fedora host deps** (debootstrap, qemu-user-static + binfmt, dosfstools, parted, etc.).
3. **Success criteria** — Image boots Pi 500 with network (wired ethernet is fine to start), **login/MBASIC on HDMI**; Fedora `build-image.sh` x86_64 and `--arch aarch64` unchanged in behavior.

## Phase 3 — Optional: mkosi + Debian + RPi repos

Defer; only if needed after pi-gen is stable. Same delineation: **not** the same artifact as Fedora AArch64 QEMU.

## Todos (tracking)

- [x] Remove/archive bootlab; grep references
- [x] Docs: Pi 500 UEFI unsupported; AArch64 vs Pi; HDMI-first Pi doc
- [x] `appliance/pi-gen/` + `build-pi-os-image.sh` + host deps in `appliance/pi-gen/README.md`
- [x] `docs/appliance_raspberry_pi_os_plan.md`; reframe `appliance_aarch64_rpi_uefi_plan.md`
- [x] Flash script + README deconflict
- [ ] (Defer) Optional `appliance/mkosi-rpi-os/` track

