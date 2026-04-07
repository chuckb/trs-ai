#!/bin/bash
# Fail fast if Milestone 1 image build prerequisites are missing.
set -euo pipefail

err() { echo "check-deps: $*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || err "missing command '$1' (install the package that provides it)"
}

need_cmd mkosi
need_cmd qemu-system-x86_64
need_cmd guestfish

# mkosi invokes dnf/rpm tooling and systemd-repart; keep checks lightweight.
need_cmd systemd-repart

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ ! -f "$ROOT/mbasic/mbasic" ]]; then
    err "mbasic sources missing at $ROOT/mbasic/mbasic — init the submodule: git submodule update --init --recursive (see README.md)."
fi

if ! mkosi --version >/dev/null 2>&1; then
    err "mkosi does not run"
fi

echo "check-deps: OK (mkosi, qemu-system-x86_64, guestfish, systemd-repart, mbasic tree)"
