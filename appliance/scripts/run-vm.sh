#!/bin/bash
# Boot the Milestone 1 image under QEMU via mkosi (same paths as build-image.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MKOSI_DIR="$ROOT/appliance/mkosi"

"$ROOT/appliance/scripts/check-deps.sh"

STAGE="${TRS_AI_MKOSI_STAGEDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/trs-ai-basic}"

if [[ ! -f "$STAGE/output/trs-ai-basic-m1.raw" ]]; then
    echo "run-vm: missing $STAGE/output/trs-ai-basic-m1.raw — run build-image.sh first." >&2
    exit 1
fi

# mkosi vm adds QEMU user networking (-nic user,virtio) when RuntimeNetwork=user (also the default).
exec mkosi \
    --directory "$MKOSI_DIR" \
    --workspace-directory "$STAGE/workspace" \
    --cache-directory "$STAGE/cache" \
    --output-directory "$STAGE/output" \
    --runtime-network=user \
    vm
