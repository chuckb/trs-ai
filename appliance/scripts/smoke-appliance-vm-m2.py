#!/usr/bin/env python3
"""
Milestone 2 appliance smoke test: boot image, exercise AILOAD (fixture backend) + RUN.

Requires: built image (build-image.sh), mkosi, pexpect. Guest must have
/etc/trs-ai/ai.env with TRS_AI_BACKEND=fixture (default image build).

Use --arch aarch64 or -a for the AArch64 image (same staging as build-image.sh --arch aarch64).

Does not modify or replace smoke-appliance-vm.py (Milestone 1).
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import time
from pathlib import Path

import appliance_image_paths as img


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


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
    arch_group = parser.add_mutually_exclusive_group()
    arch_group.add_argument(
        "--arch",
        choices=("x86_64", "aarch64", "arm64"),
        default="x86_64",
        help="Appliance architecture (default: x86_64)",
    )
    arch_group.add_argument(
        "-a",
        "--aarch64",
        action="store_const",
        const="aarch64",
        dest="arch",
        help="Same as --arch aarch64",
    )
    args = parser.parse_args()

    try:
        arch = img.normalize_arch(args.arch)
    except ValueError as e:
        print(f"smoke-appliance-vm-m2: {e}", file=sys.stderr)
        return 2

    if not shutil.which("mkosi"):
        print("smoke-appliance-vm-m2: mkosi not in PATH", file=sys.stderr)
        return 127
    if arch == "aarch64" and not shutil.which("qemu-system-aarch64"):
        print(
            "smoke-appliance-vm-m2: qemu-system-aarch64 not in PATH "
            "(dnf install qemu-system-aarch64)",
            file=sys.stderr,
        )
        return 127

    root = _repo_root()
    mkosi_dir = root / "appliance" / "mkosi"
    stage = img.default_stage_dir(arch)
    raw = stage / "output" / img.raw_image_filename(arch)
    if not raw.is_file():
        hint = (
            "./appliance/scripts/build-image.sh --arch aarch64"
            if arch == "aarch64"
            else "./appliance/scripts/build-image.sh"
        )
        print(
            f"smoke-appliance-vm-m2: missing image {raw} — run {hint} from repo root.",
            file=sys.stderr,
        )
        return 2

    cmd = img.mkosi_vm_command(mkosi_dir, stage, arch)
    print(f"smoke-appliance-vm-m2: arch={arch} spawning:", " ".join(cmd), flush=True)

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
