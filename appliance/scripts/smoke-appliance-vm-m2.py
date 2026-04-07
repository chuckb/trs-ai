#!/usr/bin/env python3
"""
Milestone 2 appliance smoke test: boot image, exercise AILOAD (fixture backend) + RUN.

Requires: built image (build-image.sh), mkosi, pexpect. Guest must have
/etc/trs-ai/ai.env with TRS_AI_BACKEND=fixture (default image build).

Does not modify or replace smoke-appliance-vm.py (Milestone 1).
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
            "smoke-appliance-vm-m2: install pexpect (e.g. sudo dnf install python3-pexpect "
            "or use a venv with pip install pexpect)",
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
        help="Log guest console to stdout",
    )
    args = parser.parse_args()

    if not shutil.which("mkosi"):
        print("smoke-appliance-vm-m2: mkosi not in PATH", file=sys.stderr)
        return 127

    root = _repo_root()
    mkosi_dir = root / "appliance" / "mkosi"
    stage = _stage()
    raw = stage / "output" / "trs-ai-basic-m1.raw"
    if not raw.is_file():
        print(
            f"smoke-appliance-vm-m2: missing image {raw} — run build-image.sh first.",
            file=sys.stderr,
        )
        return 2

    cmd = _mkosi_cmd(mkosi_dir, stage)
    print("smoke-appliance-vm-m2: spawning:", " ".join(cmd), flush=True)

    child = pexpect.spawn(
        cmd[0],
        cmd[1:],
        encoding="utf-8",
        timeout=args.boot_timeout,
        env=os.environ.copy(),
        cwd=str(root),
    )
    child.delaybeforesend = 0.05
    if args.verbose:
        child.logfile_read = sys.stdout

    _banner = r"MBASIC-\d{4}"
    _ready_prompt = r"(?im)^Ready\s*$"

    try:
        child.expect(_banner, timeout=args.boot_timeout)
        child.expect(_ready_prompt, timeout=args.boot_timeout)
        print(
            "smoke-appliance-vm-m2: saw MBASIC Ready, exercising AILOAD + RUN…",
            flush=True,
        )

        child.timeout = args.step_timeout
        child.sendline('AILOAD "smoke test prompt"')
        child.expect(r"(?i)Contacting AI", timeout=args.step_timeout)
        child.expect(r"(?i)Program loaded", timeout=args.step_timeout)
        child.expect(_ready_prompt, timeout=args.step_timeout)

        child.sendline("RUN")
        child.expect(r"AILOAD_OK", timeout=args.step_timeout)

        print("smoke-appliance-vm-m2: OK (Milestone 2 AILOAD path)", flush=True)
        return 0
    except pexpect.TIMEOUT:
        print(
            "smoke-appliance-vm-m2: TIMEOUT — see -v for console capture",
            file=sys.stderr,
        )
        return 1
    except pexpect.EOF:
        print("smoke-appliance-vm-m2: unexpected EOF", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"smoke-appliance-vm-m2: {e}", file=sys.stderr)
        return 1
    finally:
        child.close(force=True)


if __name__ == "__main__":
    raise SystemExit(main())
