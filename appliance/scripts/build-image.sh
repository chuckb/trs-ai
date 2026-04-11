#!/bin/bash
# Reproducible Milestone 1 appliance image (see appliance/mkosi/mkosi.conf).
# Default: x86_64. --arch aarch64 = Fedora AArch64 disk for QEMU (AAVMF UEFI), not Raspberry Pi.
set -euo pipefail

usage() {
    echo "usage: ./build-image.sh [--arch x86_64|aarch64|arm64] [--profile aarch64]" >&2
    echo "  Run this script directly; it invokes mkosi with the right --directory and verb (build)." >&2
    echo "  Do not run: mkosi ... ./build-image.sh (mkosi expects a verb like build, not a shell script)." >&2
    echo "  Default: x86_64 → trs-ai-basic-m1.raw under ~/.cache/trs-ai-basic (or TRS_AI_MKOSI_STAGEDIR)." >&2
    echo "  aarch64:  Fedora AArch64 for QEMU UEFI → ~/.cache/trs-ai-basic-aarch64/output/trs-ai-basic-m1-aarch64.raw" >&2
    echo "  --profile aarch64 is an alias for --arch aarch64." >&2
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
                echo "build-image: only --profile aarch64 is supported (got '$2')" >&2
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
            echo "build-image: unknown option '$1'" >&2
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
        echo "build-image: unsupported --arch '$ARCH'" >&2
        usage
        exit 1
        ;;
esac

"$ROOT/appliance/scripts/check-deps.sh" --arch "$ARCH"

chmod a-x "$MKOSI_DIR/mkosi.repart/"*.conf 2>/dev/null || true

# Workspace, package cache, and disk output must live on ONE filesystem that supports
# xattrs (mkosi uses `cp --preserve=...xattr`). If the git checkout lives on e.g.
# mergerfs/FUSE without xattr, building under the repo tree fails. Default staging
# under ~/.cache keeps everything on the same volume as mkosi's usual workspace.
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
mkdir -p "$STAGE/workspace" "$STAGE/cache" "$STAGE/output"

echo "build-image: arch=$ARCH staging under $STAGE (override with TRS_AI_MKOSI_STAGEDIR=...)"
echo "build-image: building disk image with mkosi (needs network for Fedora packages)…"

# Pi-friendly ESP (512-byte vfat logical sectors): set in appliance/mkosi/mkosi.conf [Build] Environment=.
# Host-shell exports are not passed through to systemd-repart by mkosi.

# Stage AI env for mkosi.build: mkosi does not reliably forward TRS_AI_BUILD_AI_ENV from
# the host shell into mkosi.build, so we copy into BuildSources (see appliance/mkosi/build-secrets/README.md).
MKOSI_SECRET="$MKOSI_DIR/build-secrets/ai.env"
mkdir -p "$MKOSI_DIR/build-secrets"
rm -f "$MKOSI_SECRET"
if [[ -n "${TRS_AI_BUILD_AI_ENV:-}" && -f "${TRS_AI_BUILD_AI_ENV}" ]]; then
    cp -- "${TRS_AI_BUILD_AI_ENV}" "$MKOSI_SECRET"
    echo "build-image: will install /etc/trs-ai/ai.env from TRS_AI_BUILD_AI_ENV"
elif [[ -f "$ROOT/appliance/secrets/ai.env" ]]; then
    cp -- "$ROOT/appliance/secrets/ai.env" "$MKOSI_SECRET"
    echo "build-image: will install /etc/trs-ai/ai.env from appliance/secrets/ai.env"
else
    echo "build-image: no custom ai.env staged; image will use default-ai.env (fixture AILOAD)"
fi
if [[ -f "$MKOSI_SECRET" ]]; then
    echo "build-image: staged $(grep -E '^TRS_AI_BACKEND=' "$MKOSI_SECRET" || true)"
fi

mkosi --force \
    "${MKOSI_PROFILE_ARGS[@]}" \
    --directory "$MKOSI_DIR" \
    --workspace-directory "$STAGE/workspace" \
    --cache-directory "$STAGE/cache" \
    --output-directory "$STAGE/output" \
    build

rm -f "$MKOSI_SECRET"

if [[ "$ARCH" == aarch64 ]]; then
    OUT_NAME=trs-ai-basic-m1-aarch64.raw
else
    OUT_NAME=trs-ai-basic-m1.raw
fi
echo "build-image: done. Raw image: $STAGE/output/$OUT_NAME"
