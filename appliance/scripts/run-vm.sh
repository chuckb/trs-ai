#!/bin/bash
# Boot the Fedora Milestone 1 image under QEMU via mkosi (same paths as build-image.sh).
# Default: x86_64. --arch aarch64 / -a = Fedora AArch64 for QEMU UEFI (not Raspberry Pi OS).
set -euo pipefail

usage() {
    echo "usage: run-vm.sh [--arch x86_64|aarch64|arm64] [-a]" >&2
}

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MKOSI_DIR="$ROOT/appliance/mkosi"

ARCH=x86_64
MKOSI_PROFILE_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            [[ $# -ge 2 ]] || { usage; exit 1; }
            ARCH=$2
            shift 2
            ;;
        --profile)
            [[ $# -ge 2 ]] || { usage; exit 1; }
            if [[ "$2" == aarch64 ]]; then
                ARCH=aarch64
                MKOSI_PROFILE_ARGS=(--profile aarch64)
            else
                echo "run-vm: only --profile aarch64 is supported (got '$2')" >&2
                exit 1
            fi
            shift 2
            ;;
        --aarch64|-a)
            ARCH=aarch64
            MKOSI_PROFILE_ARGS=(--profile aarch64)
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "run-vm: unknown option '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

case "$ARCH" in
    x86_64|x86-64) ARCH=x86_64 ;;
    aarch64|arm64)
        ARCH=aarch64
        MKOSI_PROFILE_ARGS=(--profile aarch64)
        ;;
    *)
        echo "run-vm: unsupported --arch '$ARCH'" >&2
        usage
        exit 1
        ;;
esac

"$ROOT/appliance/scripts/check-deps.sh" --arch "$ARCH"
if [[ "$ARCH" == aarch64 ]]; then
    command -v qemu-system-aarch64 >/dev/null 2>&1 || {
        echo "run-vm: missing qemu-system-aarch64 (dnf install qemu-system-aarch64)" >&2
        exit 1
    }
fi

CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}"
if [[ -n "${TRS_AI_MKOSI_STAGEDIR:-}" ]]; then
    STAGE="$TRS_AI_MKOSI_STAGEDIR"
else
    if [[ "$ARCH" == aarch64 ]]; then
        STAGE="$CACHE_BASE/trs-ai-basic-aarch64"
    else
        STAGE="$CACHE_BASE/trs-ai-basic"
    fi
fi

if [[ "$ARCH" == aarch64 ]]; then
    RAW_NAME=trs-ai-basic-m1-aarch64.raw
else
    RAW_NAME=trs-ai-basic-m1.raw
fi

if [[ ! -f "$STAGE/output/$RAW_NAME" ]]; then
    echo "run-vm: missing $STAGE/output/$RAW_NAME — run build-image.sh first." >&2
    exit 1
fi

# mkosi vm adds QEMU user networking (-nic user,virtio) when RuntimeNetwork=user (also the default).
exec mkosi \
    "${MKOSI_PROFILE_ARGS[@]}" \
    --directory "$MKOSI_DIR" \
    --workspace-directory "$STAGE/workspace" \
    --cache-directory "$STAGE/cache" \
    --output-directory "$STAGE/output" \
    --runtime-network=user \
    vm
