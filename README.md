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
./appliance/scripts/smoke-appliance-vm.sh   # optional: -v for guest console log
```

## Documentation

- [Milestone 1 dependencies and architecture](docs/architecture_milestone1_dependencies.md)
- [Appliance concept](docs/trs80_ai_basic_appliance_concept.md)

## License

This repository is intended to be used together with **GPL-3.0** MBASIC. The full license text is in [LICENSE](LICENSE) (same as `mbasic/LICENSE`). See [NOTICE](NOTICE) for submodule attribution and fork pointers.
