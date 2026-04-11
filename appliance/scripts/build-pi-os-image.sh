#!/bin/bash
# Clone RPi-Distro/pi-gen (pinned tag), apply TRS-AI Lite overlay, run build (Docker preferred).
# Produces Raspberry Pi OS Lite arm64 — NOT the Fedora AArch64 QEMU UEFI image.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIGEN_TAG="${TRS_AI_PIGEN_TAG:-2025-11-24-raspios-bookworm-arm64}"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}"
PIGEN_PARENT="${TRS_AI_PIGEN_DIR:-$CACHE_BASE/trs-ai-pi-gen}"
PIGEN_DIR="$PIGEN_PARENT/pi-gen"
OVERLAY="$ROOT/appliance/pi-gen"

usage() {
	echo "usage: $0 [--native] [--help]" >&2
	echo "  Builds Raspberry Pi OS Lite (64-bit) + TRS-AI. Output under pi-gen deploy/." >&2
	echo "  Default: ./build-docker.sh inside the pi-gen clone (needs Docker)." >&2
	echo "  --native: run sudo ./build.sh on the host (Debian-like + pi-gen depends)." >&2
}

NATIVE=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--native) NATIVE=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown option: $1" >&2; usage; exit 1 ;;
	esac
done

[[ -d "$ROOT/mbasic" ]] || { echo "build-pi-os-image: missing $ROOT/mbasic (submodule?)" >&2; exit 1; }

mkdir -p "$PIGEN_PARENT"

if [[ ! -d "$PIGEN_DIR/.git" ]]; then
	echo "build-pi-os-image: cloning pi-gen ($PIGEN_TAG) → $PIGEN_DIR" >&2
	git clone --depth 1 --branch "$PIGEN_TAG" https://github.com/RPi-Distro/pi-gen.git "$PIGEN_DIR"
else
	echo "build-pi-os-image: updating pi-gen in $PIGEN_DIR (fetch + checkout $PIGEN_TAG)" >&2
	git -C "$PIGEN_DIR" fetch --depth 1 origin "refs/tags/$PIGEN_TAG:refs/tags/$PIGEN_TAG" 2>/dev/null || \
		git -C "$PIGEN_DIR" fetch origin tag "$PIGEN_TAG" --depth 1
	git -C "$PIGEN_DIR" checkout -f "$PIGEN_TAG"
fi

# Lite image: skip desktop stages (see pi-gen README).
touch "$PIGEN_DIR/stage3/SKIP" "$PIGEN_DIR/stage4/SKIP" "$PIGEN_DIR/stage5/SKIP"
touch "$PIGEN_DIR/stage4/SKIP_IMAGES" "$PIGEN_DIR/stage5/SKIP_IMAGES"

cp -a "$OVERLAY/config" "$PIGEN_DIR/config"

FIRST_USER_NAME="${FIRST_USER_NAME:-pi}"
if grep -q '^FIRST_USER_NAME=' "$PIGEN_DIR/config" 2>/dev/null; then
	FIRST_USER_NAME=$(grep '^FIRST_USER_NAME=' "$PIGEN_DIR/config" | head -1 | cut -d= -f2- | tr -d "'\"" | tr -d ' ')
fi

OVERLAY_FILES="$PIGEN_DIR/.trs-ai-overlay-files"
rm -rf "$OVERLAY_FILES"
cp -a "$OVERLAY/files" "$OVERLAY_FILES"

RUN_SH="$PIGEN_DIR/stage2/99-trs-ai/00-run.sh"
mkdir -p "$(dirname "$RUN_SH")"
sed -e "s|@TRS_AI_ROOT@|$ROOT|g" \
	-e "s|@FIRST_USER_NAME@|$FIRST_USER_NAME|g" \
	"$OVERLAY/stage2/99-trs-ai/00-run.sh.in" >"$RUN_SH"
chmod +x "$RUN_SH"
cp -a "$OVERLAY/stage2/99-trs-ai/00-packages-nr" "$PIGEN_DIR/stage2/99-trs-ai/00-packages-nr"

# Optional ai.env staging (sudo build loses env — source file for 00-run.sh).
rm -f "$PIGEN_DIR/.trs-ai-build-env"
if [[ -n "${TRS_AI_BUILD_AI_ENV:-}" && -f "${TRS_AI_BUILD_AI_ENV}" ]]; then
	echo "TRS_AI_BUILD_AI_ENV=$TRS_AI_BUILD_AI_ENV" >"$PIGEN_DIR/.trs-ai-build-env"
	chmod 0600 "$PIGEN_DIR/.trs-ai-build-env"
	echo "build-pi-os-image: will install ai.env from TRS_AI_BUILD_AI_ENV" >&2
elif [[ -f "$ROOT/appliance/secrets/ai.env" ]]; then
	echo "TRS_AI_BUILD_AI_ENV=$ROOT/appliance/secrets/ai.env" >"$PIGEN_DIR/.trs-ai-build-env"
	chmod 0600 "$PIGEN_DIR/.trs-ai-build-env"
	echo "build-pi-os-image: will install ai.env from appliance/secrets/ai.env" >&2
fi

echo "build-pi-os-image: pi-gen dir=$PIGEN_DIR tag=$PIGEN_TAG" >&2

cd "$PIGEN_DIR"

if [[ "$NATIVE" -eq 1 ]]; then
	exec sudo --preserve-env=TRS_AI_BUILD_AI_ENV ./build.sh
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
	# pi-gen runs inside the container; 00-run.sh rsyncs mbasic from TRS_AI_ROOT (host repo path).
	export PIGEN_DOCKER_OPTS="${PIGEN_DOCKER_OPTS:+$PIGEN_DOCKER_OPTS }--volume=${ROOT}:${ROOT}:ro"
	exec ./build-docker.sh
fi

echo "build-pi-os-image: Docker not available. Options:" >&2
echo "  1) Install/start Docker and re-run this script, or" >&2
echo "  2) On Debian/Raspberry Pi OS with pi-gen deps: cd $PIGEN_DIR && sudo ./build.sh" >&2
echo "  3) Force native on this host: $0 --native" >&2
exit 1
