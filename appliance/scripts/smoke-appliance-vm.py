#!/usr/bin/env python3
"""
Milestone 1 appliance smoke test: boot TRS-AI image via mkosi vm, drive MBASIC over the console.

Requires: built image (build-image.sh), mkosi, pexpect (dnf install python3-pexpect).

Does not rely on guestfish or SELinux relabel. Kills the VM after success (SYSTEM would exit
exec'd mbasic and autologin would start another session). With -v, only guest output is logged
(pexpect sends are omitted so you do not see send + tty echo as duplicates).
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import time
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def _stage() -> Path:
    base = os.environ.get("TRS_AI_MKOSI_STAGEDIR")
    if base:
        return Path(base)
    xdg = os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))
    return Path(xdg) / "trs-ai-basic"


def _mkosi_cmd(mkosi_dir: Path, stage: Path) -> list[str]:
    return [
        "mkosi",
        "--directory",
        str(mkosi_dir),
        "--workspace-directory",
        str(stage / "workspace"),
        "--cache-directory",
        str(stage / "cache"),
        "--output-directory",
        str(stage / "output"),
        "vm",
    ]


def main() -> int:
    try:
        import pexpect
    except ImportError:
        print(
            "smoke-appliance-vm: install pexpect, e.g.  sudo dnf install python3-pexpect",
            file=sys.stderr,
        )
        return 125

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--boot-timeout",
        type=int,
        default=300,
        help="Seconds to wait for MBASIC Ready (default 300)",
    )
    parser.add_argument(
        "--step-timeout",
        type=int,
        default=60,
        help="Seconds per expect after boot (default 60)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Log guest→host console output to stdout (not pexpect sends; avoids echo duplicates)",
    )
    args = parser.parse_args()

    if not shutil.which("mkosi"):
        print("smoke-appliance-vm: mkosi not in PATH", file=sys.stderr)
        return 127

    root = _repo_root()
    mkosi_dir = root / "appliance" / "mkosi"
    stage = _stage()
    raw = stage / "output" / "trs-ai-basic-m1.raw"
    if not raw.is_file():
        print(f"smoke-appliance-vm: missing image {raw} — run build-image.sh first.", file=sys.stderr)
        return 2

    cmd = _mkosi_cmd(mkosi_dir, stage)
    print("smoke-appliance-vm: spawning:", " ".join(cmd), flush=True)

    child = pexpect.spawn(
        cmd[0],
        cmd[1:],
        encoding="utf-8",
        timeout=args.boot_timeout,
        env=os.environ.copy(),
        cwd=str(root),
    )
    # Avoid matching spurious "ready" in boot logs (e.g. "Already", "… is ready").
    child.delaybeforesend = 0.05
    if args.verbose:
        # logfile would log both writes to the pty and reads from it; the tty echoes input,
        # so every sendline appears twice. logfile_read is only bytes from the VM (plus echo).
        child.logfile_read = sys.stdout

    # MBASIC: banner + tip + "Ready". Use (?m)^Ready\s*$ so CRLF lines match; do not use
    # (?i)Ready alone (matches "Already"). After LOAD, expect the filename first without
    # eating the following newline so ^Ready still matches the next line.
    _banner = r"MBASIC-\d{4}"
    _ready_prompt = r"(?im)^Ready\s*$"

    try:
        child.expect(_banner, timeout=args.boot_timeout)
        child.expect(_ready_prompt, timeout=args.boot_timeout)
        print("smoke-appliance-vm: saw MBASIC Ready, exercising SAVE/LOAD/RUN…", flush=True)

        child.timeout = args.step_timeout
        child.sendline('10 PRINT "SMOKE_OK"')
        child.sendline("20 END")
        child.sendline("LIST")
        child.expect(r"10\s+PRINT", timeout=args.step_timeout)

        child.sendline('SAVE "smoke.bas"')
        # Do not require \n after the message: some tty/hvc + readline paths leave the cursor
        # on the same line so pexpect never sees a line feed and this expect would hang.
        child.expect(r"(?i)Saved to smoke\.bas", timeout=args.step_timeout)
        time.sleep(0.15)

        child.sendline("NEW")
        # Immediate-mode NEW does not re-print "Ready"; wait for echoed line + CRLF/LF, then LOAD
        # (load_from_file clears the program before reading the file, so behavior stays correct).
        child.expect(r"NEW\s*\r?\n", timeout=args.step_timeout)
        time.sleep(0.1)

        child.sendline('LOAD "smoke.bas"')
        child.expect(r"(?i)Loaded from smoke\.bas", timeout=args.step_timeout)
        child.expect(_ready_prompt, timeout=args.step_timeout)

        child.sendline("RUN")
        child.expect(r"SMOKE_OK", timeout=args.step_timeout)

        print("smoke-appliance-vm: OK (Milestone 1 session path)", flush=True)
        return 0
    except pexpect.TIMEOUT:
        print("smoke-appliance-vm: TIMEOUT — see -v for console capture", file=sys.stderr)
        return 1
    except pexpect.EOF:
        print("smoke-appliance-vm: unexpected EOF", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"smoke-appliance-vm: {e}", file=sys.stderr)
        return 1
    finally:
        child.close(force=True)


if __name__ == "__main__":
    raise SystemExit(main())
