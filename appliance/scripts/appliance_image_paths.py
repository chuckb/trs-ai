"""
Paths and mkosi flags for Fedora TRS-AI appliance images — keep in sync with build-image.sh.

``aarch64`` here means the Fedora AArch64 disk for QEMU UEFI (AAVMF), not Raspberry Pi hardware.
Pi images come from build-pi-os-image.sh / pi-gen under a separate cache layout.
"""
from __future__ import annotations

import os
from pathlib import Path


def normalize_arch(value: str) -> str:
    v = (value or "x86_64").strip().lower().replace("-", "_")
    if v in ("aarch64", "arm64"):
        return "aarch64"
    if v in ("x86_64", "x8664"):
        return "x86_64"
    raise ValueError(f"unsupported architecture {value!r} (use x86_64 or aarch64)")


def default_stage_dir(arch: str) -> Path:
    override = os.environ.get("TRS_AI_MKOSI_STAGEDIR")
    if override:
        return Path(override)
    xdg = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    if arch == "aarch64":
        return xdg / "trs-ai-basic-aarch64"
    return xdg / "trs-ai-basic"


def raw_image_filename(arch: str) -> str:
    if arch == "aarch64":
        return "trs-ai-basic-m1-aarch64.raw"
    return "trs-ai-basic-m1.raw"


def mkosi_vm_command(
    mkosi_dir: Path,
    stage: Path,
    arch: str,
    *,
    runtime_network: str | None = "user",
) -> list[str]:
    cmd: list[str] = ["mkosi"]
    if arch == "aarch64":
        cmd += ["--profile", "aarch64"]
    cmd += [
        "--directory",
        str(mkosi_dir),
        "--workspace-directory",
        str(stage / "workspace"),
        "--cache-directory",
        str(stage / "cache"),
        "--output-directory",
        str(stage / "output"),
    ]
    if runtime_network:
        cmd += ["--runtime-network", runtime_network]
    cmd.append("vm")
    return cmd
