#!/bin/bash
# Milestone 2 VM smoke: AILOAD (fixture) + RUN. Use TRS_AI_PYTHON to pick interpreter (e.g. project venv).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON="${TRS_AI_PYTHON:-python3}"
exec "$PYTHON" "$ROOT/appliance/scripts/smoke-appliance-vm-m2.py" "$@"
