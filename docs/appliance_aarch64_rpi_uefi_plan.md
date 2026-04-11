# Fedora AArch64 appliance — QEMU UEFI only

**This document describes the Fedora mkosi image built with `--arch aarch64` / `--profile aarch64`.**  
It is for **QEMU `virt` + AAVMF (EDK2)** and similar **generic AArch64 UEFI** environments.

**It is not** the Raspberry Pi OS image for Pi 500 or other Pi hardware. For Pi deployment, see [appliance_raspberry_pi_os_plan.md](appliance_raspberry_pi_os_plan.md).

## Pi 500 / UEFI on hardware (project stance)

**At the time of this project, Pi 500 booting via UEFI was not a supported or validated path** for TRS-AI. Fedora’s support for Pi-class boards lagged (including Pi 500), so **hardware deployment** uses **Raspberry Pi OS Lite** built with **pi-gen**, not this Fedora AArch64 disk.

**QEMU AArch64 UEFI** here is **emulation** of a generic UEFI/GPT disk — not a statement about Raspberry Pi firmware behavior.

## Why AArch64 uses UEFI in QEMU

Fedora’s AArch64 kernel is often shipped as **EFI zboot** (e.g. zstd-compressed). QEMU **`-kernel` direct boot** cannot load that format. The mkosi profile therefore sets **`Firmware=uefi`** so the guest boots from the ESP like a small PC.

See [`appliance/mkosi/mkosi.profiles/aarch64/mkosi.conf`](../appliance/mkosi/mkosi.profiles/aarch64/mkosi.conf).

## Workstation prerequisites (summary)

- **`qemu-user-static`** + **binfmt** for cross-arch rootfs population (same class as other AArch64 image builds).
- **`qemu-system-aarch64`** and **`edk2-aarch64`** (AAVMF) for **`mkosi vm`** and smoke tests.

Details: [architecture_milestone1_dependencies.md](architecture_milestone1_dependencies.md).

## Build and test

```bash
./appliance/scripts/build-image.sh --arch aarch64
./appliance/scripts/run-vm.sh -a
./appliance/scripts/smoke-appliance-vm.sh -a --boot-timeout 900
```

Artifact (default cache layout):  
`~/.cache/trs-ai-basic-aarch64/output/trs-ai-basic-m1-aarch64.raw`

## Flashing this `.raw` to an SD card

Only do this if you **intentionally** want that Fedora disk on a block device (e.g. another AArch64 UEFI machine). **Do not** assume it is the Pi 500 shipping image. For Pi, flash the **pi-gen** `.img` (see Raspberry Pi OS plan).

```bash
./appliance/scripts/flash-appliance-sd.sh --arch aarch64 /dev/sdX
# or pass the .raw path explicitly
```

## Packaging / compression

Same as x86: `zstd`, `sha256sum`, optional `bmaptool` — see [architecture_milestone1_dependencies.md](architecture_milestone1_dependencies.md) for examples.

## Filename note

The path **`appliance_aarch64_rpi_uefi_plan.md`** is a legacy name. Content is **Fedora AArch64 + QEMU UEFI** only; **Raspberry Pi** bring-up is documented elsewhere.
