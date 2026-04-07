#!/bin/bash
# Reproducible Milestone 1 appliance image (see appliance/mkosi/mkosi.conf).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MKOSI_DIR="$ROOT/appliance/mkosi"

"$ROOT/appliance/scripts/check-deps.sh"

chmod a-x "$MKOSI_DIR/mkosi.repart/"*.conf 2>/dev/null || true

# Workspace, package cache, and disk output must live on ONE filesystem that supports
# xattrs (mkosi uses `cp --preserve=...xattr`). If the git checkout lives on e.g.
# mergerfs/FUSE without xattr, building under the repo tree fails. Default staging
# under ~/.cache keeps everything on the same volume as mkosi's usual workspace.
STAGE="${TRS_AI_MKOSI_STAGEDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/trs-ai-basic}"
mkdir -p "$STAGE/workspace" "$STAGE/cache" "$STAGE/output"

echo "build-image: staging under $STAGE (override with TRS_AI_MKOSI_STAGEDIR=...)"
echo "build-image: building disk image with mkosi (needs network for Fedora packages)…"

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
    --directory "$MKOSI_DIR" \
    --workspace-directory "$STAGE/workspace" \
    --cache-directory "$STAGE/cache" \
    --output-directory "$STAGE/output" \
    build

rm -f "$MKOSI_SECRET"

echo "build-image: done. Raw image: $STAGE/output/trs-ai-basic-m1.raw"
