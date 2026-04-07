#!/bin/bash
# Run Milestone 1 VM smoke test (pexpect drives mkosi vm).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 "$ROOT/appliance/scripts/smoke-appliance-vm.py" "$@"
