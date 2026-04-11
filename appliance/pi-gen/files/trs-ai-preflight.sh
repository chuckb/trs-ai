#!/bin/bash
# Short status before MBASIC: IPv4 default route + TLS reachability to AI API host (remote only).
set +e

msg() { echo "TRS-AI: $*"; }

NET_OK=
for _ in $(seq 1 25); do
  if ip -4 route show default 2>/dev/null | grep -q .; then
    msg "network OK (default IPv4 route)"
    NET_OK=1
    break
  fi
  sleep 1
done
[[ -n "$NET_OK" ]] || msg "network: no default route yet — AILOAD may fail until DHCP finishes"

be="${TRS_AI_BACKEND:-fixture}"
be_lc=$(printf '%s' "$be" | tr '[:upper:]' '[:lower:]')
if [[ "$be_lc" != "remote" ]]; then
  msg "AILOAD: backend is ${be:-fixture} (skipping cloud check)"
  echo ""
  exit 0
fi

if [[ -z "$NET_OK" ]]; then
  msg "cloud: skipped (no route)"
  echo ""
  exit 0
fi

out=$(
  python3 <<'PY' 2>&1
import os
import socket
import ssl
import sys
import urllib.parse

base = (os.environ.get("TRS_AI_BASE_URL") or "https://api.openai.com/v1/chat/completions").strip()
p = urllib.parse.urlparse(base)
host = p.hostname or "api.openai.com"
port = p.port or (443 if (p.scheme or "https") != "http" else 80)
use_tls = (p.scheme or "https") != "http"
timeout = 10.0

try:
    raw = socket.create_connection((host, port), timeout=timeout)
except OSError as e:
    print(e, file=sys.stderr, flush=True)
    raise SystemExit(1)

try:
    if use_tls:
        ctx = ssl.create_default_context()
        with ctx.wrap_socket(raw, server_hostname=host):
            pass
    else:
        raw.close()
    print(f"{host}:{port}", flush=True)
except Exception as e:
    try:
        raw.close()
    except OSError:
        pass
    print(e, file=sys.stderr, flush=True)
    raise SystemExit(1)
PY
)
py=$?
out=${out//$'\n'/}
if [[ "$py" -eq 0 && -n "$out" ]]; then
  msg "cloud OK (reached $out)"
else
  msg "cloud: cannot reach API — $out (check TRS_AI_BASE_URL / DNS / HTTPS)"
fi

echo ""
