#!/bin/bash
# Milestone 3 VM smoke: AIMERGE / AIDIFF / AIAPPLY after AILOAD. Use TRS_AI_PYTHON for venv python.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON="${TRS_AI_PYTHON:-python3}"
exec "$PYTHON" "$ROOT/appliance/scripts/smoke-appliance-vm-m3.py" "$@"
