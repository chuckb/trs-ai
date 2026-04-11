#!/bin/bash
# Fail fast if Milestone 1 image build prerequisites are missing.
set -euo pipefail

err() { echo "check-deps: $*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || err "missing command '$1' (install the package that provides it)"
}

ARCH=x86_64
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            [[ $# -ge 2 ]] || err "--arch requires a value (x86_64 or aarch64)"
            ARCH=$2
            shift 2
            ;;
        -h|--help)
            echo "usage: check-deps.sh [--arch x86_64|aarch64|arm64]" >&2
            echo "  aarch64 = Fedora QEMU UEFI image deps, not Raspberry Pi OS (see build-pi-os-image.sh)." >&2
            exit 0
            ;;
        *)
            err "unknown option '$1' (try --arch x86_64|aarch64)"
            ;;
    esac
done

case "$ARCH" in
    x86_64|x86-64) ARCH=x86_64 ;;
    aarch64|arm64) ARCH=aarch64 ;;
    *) err "unsupported --arch '$ARCH' (use x86_64 or aarch64)" ;;
esac

need_cmd mkosi
need_cmd guestfish
need_cmd systemd-repart

if [[ "$ARCH" == x86_64 ]]; then
    need_cmd qemu-system-x86_64
else
    need_cmd qemu-aarch64-static
    [[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] ||
        err "binfmt for qemu-aarch64 missing — install qemu-user-static and run: sudo systemctl restart systemd-binfmt"
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ ! -f "$ROOT/mbasic/mbasic" ]]; then
    err "mbasic sources missing at $ROOT/mbasic/mbasic — init the submodule: git submodule update --init --recursive (see README.md)."
fi

if ! mkosi --version >/dev/null 2>&1; then
    err "mkosi does not run"
fi

if [[ "$ARCH" == x86_64 ]]; then
    echo "check-deps: OK (arch=x86_64: mkosi, qemu-system-x86_64, guestfish, systemd-repart, mbasic tree)"
else
    echo "check-deps: OK (arch=aarch64: mkosi, qemu-user-static/binfmt, guestfish, systemd-repart, mbasic tree)"
fi
