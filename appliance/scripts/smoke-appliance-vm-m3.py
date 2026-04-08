#!/usr/bin/env python3
"""
Milestone 3 appliance smoke: AILOAD + AIMERGE + AIDIFF + AIAPPLY + RUN.

Requires: built image, mkosi, pexpect.

Remote models are non-deterministic. This script uses **strict smoke prompts** (see
``SMOKE_AILOAD_PROMPT`` / ``SMOKE_AIMERGE_PROMPT``) that demand a tiny program with
**no INPUT**, a known ``PRINT`` token ``M3_SMOKE_OK``, and a trivial merge. That steers
the API toward a deterministic RUN without changing global backend system prompts.

If the model still emits INPUT, we answer prompts (``1``, ``M3``, empty) in rotation.
Cap: 50 INPUT rounds.

After ``RUN``, MBASIC-2025 returns to ``input()`` **without** necessarily printing another
``Ready`` (same as classic line-oriented BASIC showing ``Ok`` only in some paths). This
script waits for ``M3_SMOKE_OK``, then drains optional INPUT / optional ``Ready``; it does
**not** assume that ``RUN`` must print ``Ready``.

Do not put ASCII double-quote inside the prompt strings: MBASIC immediate-mode strings
end at the next ``"``.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import time
from pathlib import Path

# No embedded " in these — MBASIC string literals cannot escape quotes.
SMOKE_AILOAD_PROMPT = (
    "TRS-AI Milestone 3 VM smoke step A. Output JSON only with dialect and program array. "
    "Program exactly two lines: 10 PRINT must display the text M3_SMOKE_OK using normal "
    "BASIC string syntax in the generated source line, and 20 END. "
    "Forbidden: INPUT, LINE INPUT, INKEY$, INPUT$, READ, DATA. No extra lines. "
    "No user interaction."
)

SMOKE_AIMERGE_PROMPT = (
    "TRS-AI Milestone 3 VM smoke step B. Keep the same behavior: still print M3_SMOKE_OK "
    "from line 10 then END on 20. Add exactly one new line 15 REM M3SMOKEMERGE. "
    "Forbidden: INPUT, LINE INPUT, INKEY$, READ, DATA. No other new lines."
)


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def _stage() -> Path:
    base = os.environ.get("TRS_AI_MKOSI_STAGEDIR")
    if base:
        return Path(base)
    xdg = os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))
    return Path(xdg) / "trs-ai-basic"


def _after_run_smoke(
    pexpect_mod,
    child,
    ready_re: str,
    marker: str,
    total_timeout: float,
) -> None:
    """Wait for smoke marker after RUN; handle INPUT; do not require Ready (REPL quirk)."""
    end = time.time() + total_timeout
    input_re = r"(?im)(:\s*\?\s*$|^\?\s*$)"
    replies = ("1", "M3", "")
    max_inputs = 50
    inputs_sent = 0

    # Phase 1: must see marker (do not match Ready — stale Ready may precede RUN in buffer).
    found_marker = False
    while time.time() < end:
        rem = end - time.time()
        if rem <= 0:
            break
        try:
            idx = child.expect(
                [marker, input_re],
                timeout=min(120.0, rem),
            )
        except pexpect_mod.TIMEOUT:
            continue
        if idx == 0:
            found_marker = True
            break
        inputs_sent += 1
        if inputs_sent > max_inputs:
            raise pexpect_mod.TIMEOUT("RUN: too many INPUT prompts before marker")
        child.sendline(replies[(inputs_sent - 1) % len(replies)])

    if not found_marker:
        raise pexpect_mod.TIMEOUT("RUN: timed out before smoke marker")

    # Phase 2: program may still prompt for INPUT, or MBASIC may print Ready, or neither.
    while time.time() < end:
        rem = end - time.time()
        if rem <= 0:
            return
        try:
            idx = child.expect(
                [input_re, ready_re],
                timeout=min(5.0, rem),
            )
        except pexpect_mod.TIMEOUT:
            return
        if idx == 0:
            inputs_sent += 1
            if inputs_sent > max_inputs:
                raise pexpect_mod.TIMEOUT("RUN: too many INPUT prompts after marker")
            child.sendline(replies[(inputs_sent - 1) % len(replies)])
        else:
            return


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
            "smoke-appliance-vm-m3: install pexpect (e.g. sudo dnf install python3-pexpect "
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
        print("smoke-appliance-vm-m3: mkosi not in PATH", file=sys.stderr)
        return 127

    root = _repo_root()
    mkosi_dir = root / "appliance" / "mkosi"
    stage = _stage()
    raw = stage / "output" / "trs-ai-basic-m1.raw"
    if not raw.is_file():
        print(
            f"smoke-appliance-vm-m3: missing image {raw} — run build-image.sh first.",
            file=sys.stderr,
        )
        return 2

    cmd = _mkosi_cmd(mkosi_dir, stage)
    print("smoke-appliance-vm-m3: spawning:", " ".join(cmd), flush=True)

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
            "smoke-appliance-vm-m3: Ready — AILOAD, AIMERGE, AIDIFF, AIAPPLY, RUN…",
            flush=True,
        )

        child.timeout = args.step_timeout

        child.sendline(f'AILOAD "{SMOKE_AILOAD_PROMPT}"')
        child.expect(r"(?i)Contacting AI", timeout=args.step_timeout)
        child.expect(r"(?i)Program loaded", timeout=args.step_timeout)
        child.expect(_ready_prompt, timeout=args.step_timeout)

        child.sendline(f'AIMERGE "{SMOKE_AIMERGE_PROMPT}"')
        child.expect(r"(?i)Contacting AI", timeout=args.step_timeout)
        child.expect(r"(?i)AI CHANGES PENDING", timeout=args.step_timeout)
        child.expect(_ready_prompt, timeout=args.step_timeout)

        child.sendline("AIDIFF")
        # Do not match fixture-only patterns (+ REM AIMERGE); remote diffs look different.
        child.expect(_ready_prompt, timeout=args.step_timeout)

        child.sendline("AIAPPLY")
        child.expect(r"(?i)AI CHANGES APPLIED", timeout=args.step_timeout)
        child.expect(_ready_prompt, timeout=args.step_timeout)

        child.sendline("RUN")
        run_timeout = float(max(args.step_timeout, 120))
        try:
            _after_run_smoke(pexpect, child, _ready_prompt, "M3_SMOKE_OK", run_timeout)
        except pexpect.TIMEOUT:
            print(
                "smoke-appliance-vm-m3: RUN did not produce M3_SMOKE_OK in time "
                "(model ignored constraints or program hung).",
                file=sys.stderr,
            )
            return 1

        print("smoke-appliance-vm-m3: OK (Milestone 3 pending/apply path)", flush=True)
        return 0
    except pexpect.TIMEOUT:
        print(
            "smoke-appliance-vm-m3: TIMEOUT — see -v for console capture",
            file=sys.stderr,
        )
        return 1
    except pexpect.EOF:
        print("smoke-appliance-vm-m3: unexpected EOF", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"smoke-appliance-vm-m3: {e}", file=sys.stderr)
        return 1
    finally:
        child.close(force=True)


if __name__ == "__main__":
    raise SystemExit(main())
