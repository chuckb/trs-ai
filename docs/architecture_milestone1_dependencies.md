# Milestone 1: Host dependencies and architecture notes

This document lists what you need on a **Fedora** (or Fedora-like) **development host** to implement and verify [Milestone 1 in the concept doc](./trs80_ai_basic_appliance_concept.md): a bootable Linux image under QEMU that launches directly into a BASIC environment with `NEW`, `LIST`, `RUN`, `SAVE`, `LOAD`, and local file persistence.

Milestone 1 does **not** require AI backends, Ollama, or frozen-binary packaging yet; those appear in later milestones. You may still want compiler tooling early if you plan to drop a **Nuitka** or **PyInstaller** binary into the guest image in the same milestone.

---

## Milestone 1 scope (reminder)

| In scope | Out of scope (later milestones) |
|----------|----------------------------------|
| Bootable Linux guest image | Remote/local LLM APIs |
| Auto-launch BASIC on tty (no login UX) | `AILOAD` and related commands |
| Core BASIC commands and program files | Ollama, `AIMODEL`, first-boot AI wizard |
| QEMU for boot/test | Retro polish as primary goal |

---

## Architecture (host vs guest)

```text
┌─────────────────────────────────────────┐
│  Fedora host (your laptop/CI)           │
│  • QEMU (runs the appliance disk/image) │
│  • Python + git (develop/fork MBASIC)   │
│  • Image build tool (e.g. mkosi)        │
│  • Optional: Nuitka/PyInstaller chain   │
└─────────────────┬───────────────────────┘
                  │ qemu-system-x86_64 …
                  ▼
┌─────────────────────────────────────────┐
│  Minimal Linux guest (appliance)        │
│  • systemd (or minimal init)            │
│  • getty/autologin → BASIC on console   │
│  • Writable workspace for SAVE/LOAD     │
│  • Either: frozen binary OR Python+app  │
└─────────────────────────────────────────┘
```

The concept doc prefers a **frozen** Python app in the long run; for the smallest **first** image, some teams still ship **Python 3 + application tree** inside the guest for Milestone 1 only, then switch to a standalone binary before calling the milestone “done” for product polish. This doc lists dependencies for both paths.

---

## Repository layout (MBASIC)

The [`mbasic/`](../mbasic/) tree is a **git submodule** pointing at **[chuckb/mbasic](https://github.com/chuckb/mbasic)** (fork of [avwohl/mbasic](https://github.com/avwohl/mbasic)). After `git clone`, run `git submodule update --init --recursive` so `mbasic/mbasic` exists before building. See the root [README.md](../README.md).

---

## Appliance image build (Milestone 1 — implemented)

The Fedora guest is assembled **as code** under [`appliance/mkosi/`](../appliance/mkosi/):

| File | Role |
|------|------|
| [`mkosi.conf`](../appliance/mkosi/mkosi.conf) | Fedora 42, minimal package set, `Bootable=yes`, UKI + systemd-boot |
| [`mkosi.build`](../appliance/mkosi/mkosi.build) | Copies [`mbasic/`](../mbasic/) into `/opt/trs-ai/mbasic` on the image |
| [`mkosi.postinst.chroot`](../appliance/mkosi/mkosi.postinst.chroot) | `basic` user (UID 1000), getty autologin, launcher script, **`tmpfiles.d`** so `/home/basic` and `~/.mbasic` stay owned by `basic` (MBASIC settings need a writable home) |
| [`mkosi.repart/*.conf`](../appliance/mkosi/mkosi.repart/) | ESP + **writable ext4 root** (so `SAVE`/`LOAD` persist on the disk image) |

Host orchestration (dependency check + mkosi CLI flags):

| Script | Role |
|--------|------|
| [`appliance/scripts/check-deps.sh`](../appliance/scripts/check-deps.sh) | **`--arch x86_64`** (default): `mkosi`, `qemu-system-x86_64`, `guestfish`, `systemd-repart`, `mbasic/mbasic`. **`--arch aarch64`**: `qemu-user-static` + binfmt, no system QEMU required for build |
| [`appliance/scripts/build-image.sh`](../appliance/scripts/build-image.sh) | Builds `trs-ai-basic-m1.raw` (default) or **`--arch aarch64`** → `trs-ai-basic-m1-aarch64.raw` (**Fedora / QEMU UEFI**, not Pi hardware) |
| [`appliance/scripts/build-pi-os-image.sh`](../appliance/scripts/build-pi-os-image.sh) | **Raspberry Pi OS Lite** (pi-gen) + TRS-AI; output under cached pi-gen **`deploy/`** — see [appliance_raspberry_pi_os_plan.md](appliance_raspberry_pi_os_plan.md) |
| [`appliance/scripts/verify-image-contents.sh`](../appliance/scripts/verify-image-contents.sh) | `guestfish` smoke check for MBASIC payload |
| [`appliance/scripts/run-vm.sh`](../appliance/scripts/run-vm.sh) | `mkosi vm` with the same staging paths as the build; **`--arch aarch64`** / **`-a`** for AArch64 (needs `qemu-system-aarch64`) |
| [`appliance/scripts/flash-appliance-sd.sh`](../appliance/scripts/flash-appliance-sd.sh) | **`dd`** whole-disk image to SD/USB — default **`--arch x86_64`** Fedora `.raw`; use **`--arch aarch64`** only for Fedora QEMU UEFI `.raw`; pass a **`.img`** path for **pi-gen** / Pi OS |
| [`appliance/scripts/smoke-appliance-vm.sh`](../appliance/scripts/smoke-appliance-vm.sh) | **Automated Milestone 1 test**: boots `mkosi vm`, drives MBASIC (`LIST` / `SAVE` / `NEW` / `LOAD` / `RUN`), then kills the VM; **`--arch aarch64`** / **`-a`** for AArch64 |
| [`appliance/scripts/smoke-appliance-vm.py`](../appliance/scripts/smoke-appliance-vm.py) | Python + **pexpect**; uses [`appliance_image_paths.py`](../appliance/scripts/appliance_image_paths.py) for staging / `mkosi` flags |
| [`appliance/scripts/smoke-appliance-vm-m2.sh`](../appliance/scripts/smoke-appliance-vm-m2.sh) | **Milestone 2**: `AILOAD` + `RUN` (fixture backend); optional **`TRS_AI_PYTHON`** for interpreter |

**Automated appliance test:** install **`python3-pexpect`** (`sudo dnf install python3-pexpect`), build the image, then run **`./appliance/scripts/smoke-appliance-vm.sh`** (optional **`-v`** for full console capture). Default boot wait is **300s**; use **`--boot-timeout 600`** on slow hosts or without KVM. CI jobs need **`/dev/kvm`** for reasonable speed, or a much larger timeout if QEMU falls back to TCG. **AArch64 image on an x86 host:** **`./appliance/scripts/smoke-appliance-vm.sh -a --boot-timeout 900`** (TCG is slow; install **`qemu-system-aarch64`**).

**SELinux on your workstation (optional, one-time):** With **Enforcing**, `guestfish`/`qemu` often hits policy on disk images under **`~/.cache`** (AVC noise or failed verify). This repo does **not** run `chcon`/`sudo` after builds. For a personal dev box where you want zero friction, pick one:

- **Permissive** (policy still loads; denials are logged but not blocked): edit **`/etc/selinux/config`** and set **`SELINUX=permissive`**, then **`sudo setenforce Permissive`** or reboot.
- **Off:** **`SELINUX=disabled`** in **`/etc/selinux/config`**, then reboot (not live-tunable).

That is a **machine-wide** choice—only do it if you accept the tradeoff on that system.

**Staging directory (important):** mkosi runs `cp --preserve=…,xattr` while assembling the image. If the repository lives on a filesystem **without extended attribute support** (some FUSE/mergerfs/NAS mounts), builds can fail. By default, `build-image.sh` puts workspace, package cache, and output under **`${XDG_CACHE_HOME:-$HOME/.cache}/trs-ai-basic/`** so all of that stays on one typical local filesystem. Override with:

```bash
export TRS_AI_MKOSI_STAGEDIR=/var/tmp/my-xattr-capable-staging
```

**Python on the host (local pytest / MBASIC dev only):** use a **virtual environment on your machine** so dev dependencies (pytest, pexpect, etc.) are isolated. **There is no canonical venv path** in the repo—create one wherever you prefer, for example:

```bash
python3 -m venv ~/.local/venvs/trs-ai-dev   # or mbasic/.venv, ~/pyenvs/trs-ai, etc.
source ~/.local/venvs/trs-ai-dev/bin/activate
cd mbasic
pip install -e ".[dev]"
python -m pytest …
```

CI and other maintainers only need an environment where `mbasic` is installed **editable** with the **`[dev]`** extra; how that venv is created and where it lives is configurable.

**Guest (appliance image):** MBASIC is started with **`/usr/bin/python3`** from Fedora packages. The image does **not** install or use `venv`, `pip`, or a project-specific virtual environment—the appliance is meant to “just work” without that layer. See [`mkosi.postinst.chroot`](../appliance/mkosi/mkosi.postinst.chroot) (`exec /usr/bin/python3 /opt/trs-ai/mbasic/mbasic …`).

Documented again in the root [README.md](../README.md) under **Host Python (development and tests only)**.

**Typical workflow**

```bash
./appliance/scripts/check-deps.sh
./appliance/scripts/build-image.sh
./appliance/scripts/verify-image-contents.sh
./appliance/scripts/smoke-appliance-vm.sh
./appliance/scripts/run-vm.sh
```

The guest should boot to the MBASIC CLI banner and a **`Ready`** prompt (see [`mbasic` CLI backend](../mbasic/src/ui/cli.py)); use `SYSTEM` to exit if needed.

**QEMU / Konsole:** [`mkosi.conf`](../appliance/mkosi/mkosi.conf) sets **`[Runtime] Firmware=linux`** (x86_64 default) so `mkosi vm` uses **direct kernel boot** (`trs-ai-basic-m1.vmlinuz` + `.initrd`) instead of relying on in-VM UEFI scanning the ESP. The UEFI-only path often hits OVMF errors such as `BdsDxe: failed to load Boot0002 "UEFI Misc Device" … Not Found` when NVRAM boot entries do not match the emulated PCI topology. **AArch64** (`--profile aarch64`): [`mkosi.profiles/aarch64/mkosi.conf`](../appliance/mkosi/mkosi.profiles/aarch64/mkosi.conf) sets **`Firmware=uefi`** because Fedora’s AArch64 `vmlinuz` is **EFI zboot (zstd)** and QEMU’s **`-kernel`** cannot load it (`unable to handle EFI zboot image with "zstd"`); install **`edk2-aarch64`** for `mkosi vm` / smoke tests. The **ESP must contain** `/efi` and `/boot` payloads: [`mkosi.repart/00-esp.conf`](../appliance/mkosi/mkosi.repart/00-esp.conf) needs **`CopyFiles=/efi:/`** and **`CopyFiles=/boot:/`** (same as mkosi’s built-in repart defaults). Omitting them leaves an **empty vfat ESP** while x86 **`Firmware=linux`** still boots via **`-kernel`** — so the bug only shows up for **UEFI** guests (e.g. AArch64 QEMU). **Raspberry Pi hardware** uses the **pi-gen** image, not this Fedora ESP layout.

---

## Fedora: recommended DNF packages

Install as root (or with `sudo`).

### Required on the host (minimal set)

| Purpose | Fedora packages |
|--------|------------------|
| Boot and test the appliance | `qemu-system-x86-core` |
| KVM acceleration (optional but recommended) | `qemu-kvm` (often pulled in with the above); ensure your user is in the `kvm` group |
| Clone and build the interpreter | `git`, `python3` |
| Isolated Python deps for MBASIC | `python3-pip` (or use **pipx**/a pinned **uv** binary from upstream—your choice for reproducibility; see below) |

One-shot example:

```bash
sudo dnf install -y git python3 python3-pip qemu-system-x86-core
```

If you want virtio/GUI convenience for QEMU (not strictly required for serial-only appliances):

```bash
sudo dnf install -y qemu-ui-gtk
```

### Strongly recommended for reproducible images

| Purpose | Fedora packages |
|--------|------------------|
| Declarative, repeatable disk images | `mkosi` |
| Fetch/extract tarballs inside mkosi builds | `tar`, `xz` (usually present) |
| Manipulate disk images from scripts | `guestfs-tools` (used by `verify-image-contents.sh`; provides `guestfish` and `virt-filesystems`) |
| Partition tool mkosi invokes | `systemd-repart` / `systemd-udev` (usually present with systemd) |

Example:

```bash
sudo dnf install -y mkosi guestfs-tools
```

`mkosi` targets **Fedora 42** in [`appliance/mkosi/mkosi.conf`](../appliance/mkosi/mkosi.conf); adjust `Release=` to match your target.

### Optional: full-screen MBASIC (curses) on the host

MBASIC’s core interpreter uses only the Python standard library. The **full-screen** backend uses **Urwid** ([`pyproject.toml` optional `curses` extra](../mbasic/pyproject.toml)).

- **Fedora**: try `dnf install python3-urwid` if available; otherwise install Urwid into a venv with pip.
- **ncurses**: Fedora’s `python3` build already includes the `_curses` extension; no extra package is normally needed for curses support.

### Optional: frozen binary for the guest (Nuitka path)

If you compile a standalone binary on Fedora before copying it into the image:

```bash
sudo dnf install -y gcc gcc-c++ make patchelf zlib-devel
```

Install **Nuitka** (and any plugins) via pip in a dedicated environment; pin versions in a lockfile or constraints file for reproducibility.

### Optional: PyInstaller fallback

Similar toolchain: `gcc`, `zlib-devel`, and often `glibc-devel` are already present on a typical dev system. Pin PyInstaller in a constraints file.

### Raspberry Pi OS image (optional hardware path)

- **Docker** (recommended on Fedora): `build-pi-os-image.sh` runs pi-gen’s **`build-docker.sh`**. Install **`docker`** and ensure the daemon runs; **`qemu-user-static`** on the host is still used for **binfmt** registration before the container run.
- Full detail: [appliance_raspberry_pi_os_plan.md](appliance_raspberry_pi_os_plan.md) and [`appliance/pi-gen/README.md`](../appliance/pi-gen/README.md).

### Explicitly **not** needed for Milestone 1

- **Ollama**, **CUDA**, large model weights (Milestone 5).
- **Podman/Docker** — not required for **Fedora mkosi** Milestone 1; **Docker** is recommended only if you build the **Pi OS** image via pi-gen on Fedora.
- **Desktop environment** on the guest image — contradicts the appliance goal.

---

## Python / MBASIC (application)

- **Interpreter**: Python **≥ 3.8** per MBASIC; use **3.11+** on Fedora for a supported stack.
- **Runtime deps**: core MBASIC has **no** mandatory third-party packages (`dependencies = []` in [`mbasic/pyproject.toml`](../mbasic/pyproject.toml)).
- **Development**: use a **venv** and `pip install -e ".[dev,curses]"` from the `mbasic` directory when you need tests or Urwid.

Reproducibility habit: commit a **`requirements-lock.txt`** (or `uv.lock`) generated from a known environment, and document the Python minor version.

---

## Guest image contents (checklist)

The current recipe keeps the guest small but bootable:

| Component | Notes |
|-----------|--------|
| Linux kernel + systemd | Fedora packages from [`mkosi.conf`](../appliance/mkosi/mkosi.conf); no custom kernel |
| `getty` autologin | User `basic` on tty1, serial (`ttyS*`), and virtio console (`hvc0`); `.bash_profile` starts MBASIC on those TTYs (`mkosi vm` uses **hvc0**, not tty1) |
| BASIC payload | `/opt/trs-ai/mbasic` (full tree) run with **`python3` … `--ui cli`** |
| Writable root | ext4 root partition; default cwd `/home/basic` for `SAVE` / `LOAD` |
| Networking | Installed (`iproute`, `iputils`) but not required for M1 BASIC |

Size discipline: **WithDocs=no**, no desktop stack; avoid adding large stacks until later milestones.

---

## Reproducibility practices (short)

1. **Pin the base OS** in the mkosi (or equivalent) definition: release version, architecture, and package set.
2. **Pin Python tooling**: lockfile for pip/uv; same Python minor in CI and docs.
3. **Pin QEMU** major version in CI when running automated smoke tests (avoids “works on my laptop” drift).
4. **Document the exact `qemu-system-x86_64` command line** (machine type, drives, netdev or `-nic none`) in the repo when the image is buildable.
5. **Optional CI**: run image build + “boot and grep for READY” in **GitHub Actions** or **GitLab CI** using the same manifest; Fedora container image as job `FROM` is enough for **build**; **test** may need KVM (`/dev/kvm`) or a slower TCG fallback.

---

## Quick verification checklist

After install:

- `qemu-system-x86_64 --version` prints a version string.
- `python3 --version` ≥ 3.8 (prefer 3.11+).
- From `mbasic/`, `python3 -m venv .venv && source .venv/bin/activate && pip install -e .` allows running the CLI entry point defined in MBASIC’s packaging (exact module/CLI name per MBASIC docs).
- When the appliance image exists: QEMU boots it and you see a **`READY`** (or equivalent) prompt without a Linux login.

---

## Summary: minimum Fedora install for an assistant to execute Milestone 1

For a **human or agent** to implement and test Milestone 1 on Fedora, the smallest reasonable set is:

```text
git python3 python3-pip qemu-system-x86-core mkosi guestfs-tools
```

Add **compiler + patchelf + zlib-devel** when you add a **Nuitka** (or PyInstaller) binary to the guest. Add **Ollama** and networking only when you leave Milestone 1.
