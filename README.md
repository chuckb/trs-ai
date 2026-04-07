# TRS-AI

Bootable **Fedora** appliance (Milestone 1) that lands in **MBASIC** on the console, with `SAVE` / `LOAD` on a writable disk image. Image build is **mkosi**; orchestration lives under [`appliance/`](appliance/).

## MBASIC submodule

Interpreter sources are **not** vendored as a plain copy in this repo: use the **[chuckb/mbasic](https://github.com/chuckb/mbasic)** fork as a **git submodule** at `mbasic/` (upstream: [avwohl/mbasic](https://github.com/avwohl/mbasic)).

### First clone

```bash
git clone --recurse-submodules https://github.com/chuckb/trs-ai.git
cd trs-ai
```

### Already cloned without submodules

```bash
git submodule update --init --recursive
```

### Replacing a full `mbasic/` tree with the submodule

If you previously had MBASIC checked out as normal files and want to switch:

```bash
rm -rf mbasic
git submodule update --init --recursive
```

(If `mbasic/` was tracked by git, remove it from the index first: `git rm -rf mbasic`, then add the submodule.)

### First-time publish to `chuckb/trs-ai` (maintainer)

If this tree already contains a **full** `mbasic/` directory (not a submodule gitlink yet), Git will not let you `submodule add` into a non-empty path. Typical sequence:

```bash
git init
mv mbasic mbasic.vendor
git submodule add https://github.com/chuckb/mbasic.git mbasic
git submodule update --init --recursive
# diff or sync any local-only changes from mbasic.vendor/, then rm -rf mbasic.vendor
git add appliance docs README.md NOTICE LICENSE .gitignore .gitmodules mbasic
```

`git submodule add` records the URL in **`.gitmodules`** and adds **`mbasic`** as a gitlink; commit those with the rest of the tree. (If a hand-written `.gitmodules` was already present, Git updates it to match.)

## Host Python (development and tests only)

**The bootable appliance does not use a virtualenv.** The guest runs MBASIC with the image’s **system** `/usr/bin/python3` and the tree under `/opt/trs-ai/mbasic` (see [`mkosi.postinst.chroot`](appliance/mkosi/mkosi.postinst.chroot)); nothing in the image expects `venv` or `pip`.

On your **workstation**, use any Python virtual environment you like for editable MBASIC installs, pytest, and tooling. Path is entirely up to you; there is no required location in the repo.

```bash
python3 -m venv /path/you/prefer/trs-ai-dev    # or mbasic/.venv, uv, pipx, etc.
source /path/you/prefer/trs-ai-dev/bin/activate
cd mbasic
pip install -e ".[dev]"   # once, or after dependency changes
python -m pytest tests/regression/ai/ -v
```

Activate your venv **before** `pip` or `pytest` so dependencies stay off the system Python. Example: `source ~/pyenvs/trs-ai/bin/activate` if you use that layout (optional; any path works).

Optional convenience: if you keep a venv in a fixed place, your shell can `source …/bin/activate` or set `PATH` to that venv’s `bin`—for example some maintainers use `~/pyenvs/trs-ai`, which is only a habit, not something the project enforces.

More detail: [Milestone 1 architecture / dependencies](docs/architecture_milestone1_dependencies.md) (host vs guest).

## Building the Milestone 1 image

On a Fedora-like host with `mkosi`, QEMU, `guestfish`, etc.:

```bash
./appliance/scripts/check-deps.sh
./appliance/scripts/build-image.sh
```

The raw disk image is written under `${XDG_CACHE_HOME:-$HOME/.cache}/trs-ai-basic/output/` by default (see script output). Override staging with `TRS_AI_MKOSI_STAGEDIR` if your checkout lives on a filesystem without xattrs.

## Run and smoke test

```bash
./appliance/scripts/run-vm.sh
./appliance/scripts/smoke-appliance-vm.sh   # Milestone 1: SAVE/LOAD/RUN (optional: -v)
./appliance/scripts/smoke-appliance-vm-m2.sh   # Milestone 2: AILOAD + RUN (fixture backend)
```

For the M2 script, set **`TRS_AI_PYTHON`** if you want a specific interpreter (e.g. your venv’s `python3`) instead of `PATH`’s `python3`. The guest image does not use a venv.

## Documentation

- [Milestone 1 dependencies and architecture](docs/architecture_milestone1_dependencies.md)
- [Milestone 2: `AILOAD` and AI env](docs/architecture_milestone2_aiload.md)
- [Appliance concept](docs/trs80_ai_basic_appliance_concept.md)

## License

This repository is intended to be used together with **GPL-3.0** MBASIC. The full license text is in [LICENSE](LICENSE) (same as `mbasic/LICENSE`). See [NOTICE](NOTICE) for submodule attribution and fork pointers.
