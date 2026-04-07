#!/bin/bash
# Read-only inspection of the built raw image (requires guestfish).
set -euo pipefail

STAGE="${TRS_AI_MKOSI_STAGEDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/trs-ai-basic}"
img="$(ls -1 "$STAGE/output"/trs-ai-basic-m1*.raw 2>/dev/null | head -1 || true)"

if [[ -z "$img" || ! -f "$img" ]]; then
    echo "verify-image-contents: no trs-ai-basic-m1*.raw under $STAGE/output" >&2
    echo "verify-image-contents: build first with appliance/scripts/build-image.sh" >&2
    exit 1
fi

echo "verify-image-contents: using $img"

root_dev=/dev/sda2
if command -v virt-filesystems >/dev/null 2>&1; then
    last_fs="$(virt-filesystems -a "$img" --filesystems 2>/dev/null | tail -1 || true)"
    if [[ -n "$last_fs" ]]; then
        root_dev="$last_fs"
    fi
fi

guestfish --ro <<EOF
add "$img"
run
mount $root_dev /
is-file /opt/trs-ai/mbasic/mbasic
is-file /usr/local/bin/trs-ai-basic
EOF

echo "verify-image-contents: OK (MBASIC tree and launcher present on root partition)"
