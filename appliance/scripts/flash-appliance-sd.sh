#!/bin/bash
# Write a whole-disk image to an SD card / USB block device with dd.
# DESTRUCTIVE: overwrites the entire device. Triple-check of= (see lsblk).
set -euo pipefail

usage() {
    echo "usage: flash-appliance-sd.sh [--arch aarch64|x86_64] [--yes] /dev/DISK" >&2
    echo "   or: flash-appliance-sd.sh IMAGE.raw|IMAGE.img [--yes] /dev/DISK" >&2
    echo "" >&2
    echo "  Fedora mkosi appliances (GPT .raw from build-image.sh):" >&2
    echo "    Default --arch is x86_64 (NOT Raspberry Pi). Use --arch aarch64 only for" >&2
    echo "    Fedora AArch64 QEMU UEFI images — do not assume Pi hardware." >&2
    echo "  Raspberry Pi OS (pi-gen .img from build-pi-os-image.sh):" >&2
    echo "    Pass the .img path explicitly as the first argument." >&2
    echo "  Examples: /dev/sdX, /dev/mmcblk0 — NOT /dev/sdX1 or /dev/mmcblk0p1." >&2
    echo "  Omit --yes for an interactive confirmation prompt." >&2
}

err() { echo "flash-appliance-sd: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARCH=x86_64
IMAGE=""
YES=0
POS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            [[ $# -ge 2 ]] || err "--arch needs a value"
            ARCH=$2
            shift 2
            ;;
        --yes|-y)
            YES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            POS+=("$1")
            shift
            ;;
    esac
done

case "$ARCH" in
    aarch64|arm64) ARCH=aarch64 ;;
    x86_64|x86-64) ARCH=x86_64 ;;
    *) err "unsupported --arch '$ARCH'" ;;
esac

if [[ ${#POS[@]} -eq 2 ]]; then
    IMAGE=${POS[0]}
    DISK=${POS[1]}
elif [[ ${#POS[@]} -eq 1 ]]; then
    DISK=${POS[0]}
    CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}"
    if [[ -n "${TRS_AI_MKOSI_STAGEDIR:-}" ]]; then
        STAGE="$TRS_AI_MKOSI_STAGEDIR"
    elif [[ "$ARCH" == aarch64 ]]; then
        STAGE="$CACHE_BASE/trs-ai-basic-aarch64"
    else
        STAGE="$CACHE_BASE/trs-ai-basic"
    fi
    if [[ "$ARCH" == aarch64 ]]; then
        IMAGE="$STAGE/output/trs-ai-basic-m1-aarch64.raw"
    else
        IMAGE="$STAGE/output/trs-ai-basic-m1.raw"
    fi
else
    usage
    exit 1
fi

[[ -f "$IMAGE" ]] || err "image not found: $IMAGE"

case "$DISK" in
    /dev/sd[a-z]) ;;
    /dev/mmcblk[0-9]) ;;
    /dev/nvme[0-9]n[0-9]) ;;
    *)
        err "refuse '$DISK' — use a whole disk (e.g. /dev/sde or /dev/mmcblk0), not a partition (*1, *p1)"
        ;;
esac

[[ -b "$DISK" ]] || err "not a block device: $DISK"

if [[ "$YES" -ne 1 ]]; then
    echo "flash-appliance-sd: about to run dd from:" >&2
    echo "  if=$IMAGE" >&2
    echo "  of=$DISK" >&2
    echo "flash-appliance-sd: current block devices (lsblk):" >&2
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS,MODEL 2>/dev/null || lsblk >&2
    echo >&2
    read -r -p "Type YES in capitals to erase $DISK: " confirm
    [[ "$confirm" == YES ]] || err "aborted (no match for YES)"
fi

echo "flash-appliance-sd: writing… (this can take several minutes)" >&2
sudo dd if="$IMAGE" of="$DISK" bs=4M status=progress conv=fsync
sync
echo "flash-appliance-sd: done. Safe to remove the card/drive after ejecting/unmounting." >&2
