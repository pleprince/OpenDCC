# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""pixi discovery, installation and invocation.

pixi is the only thing the build needs from the outside world. If it is missing it is installed
for the current user ("pixi install" does that upstream), because everything else -- compiler
runtime, Qt, USD, cmake, ninja -- comes from pixi environments.
"""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

INSTALL_SH = "https://pixi.sh/install.sh"
INSTALL_PS1 = "https://pixi.sh/install.ps1"


class PixiError(RuntimeError):
    pass


def platform_key(machine: str | None = None) -> str:
    """The pixi/conda platform key for this machine ("osx-arm64", "linux-64", "win-64")."""
    system = sys.platform
    mach = (machine or platform.machine()).lower()
    if system == "darwin":
        return "osx-arm64" if mach in ("arm64", "aarch64") else "osx-64"
    if system.startswith("linux"):
        return "linux-aarch64" if mach in ("arm64", "aarch64") else "linux-64"
    if system in ("win32", "cygwin", "msys"):
        return "win-arm64" if mach in ("arm64", "aarch64") else "win-64"
    raise PixiError(f"unsupported platform: {system}/{mach}")


def exe(name: str) -> str:
    return name + (".exe" if platform_key().startswith("win") else "")


def _candidates() -> list[Path]:
    home = Path.home()
    win = platform_key().startswith("win")
    names = ["pixi.exe", "pixi"] if win else ["pixi"]
    roots = [
        home / ".pixi" / "bin",
        home / ".local" / "bin",
        Path("/usr/local/bin"),
        Path("/opt/homebrew/bin"),
    ]
    return [root / name for root in roots for name in names]


def find() -> str | None:
    found = shutil.which("pixi")
    if found:
        return found
    for candidate in _candidates():
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def ensure(verbose: bool = True) -> str:
    """Return a pixi executable path, installing pixi for the current user when needed."""
    found = find()
    if found:
        return found
    if verbose:
        print("pixi not found; installing it for the current user", flush=True)
    if platform_key().startswith("win"):
        script = _download(INSTALL_PS1)
        cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)]
    else:
        script = _download(INSTALL_SH)
        cmd = [shutil.which("sh") or "/bin/sh", str(script)]
    result = subprocess.run(cmd, check=False)
    if result.returncode != 0:
        raise PixiError(
            f"pixi installation failed (exit {result.returncode}); run '{cmd}' yourself and retry"
        )
    found = find()
    if not found:
        raise PixiError(
            "pixi was installed but is not on PATH or in ~/.pixi/bin; "
            "restart your shell so the installer's PATH change takes effect"
        )
    if verbose:
        print(f"pixi installed at {found}", flush=True)
    return found


def _download(url: str) -> Path:
    suffix = ".ps1" if url.endswith(".ps1") else ".sh"
    handle, path = tempfile.mkstemp(prefix="pixi-install-", suffix=suffix)
    os.close(handle)
    with urllib.request.urlopen(url) as response, open(path, "wb") as out:
        out.write(response.read())
    return Path(path)


def version(pixi: str) -> str:
    out = subprocess.run([pixi, "--version"], capture_output=True, text=True, check=True)
    return out.stdout.strip()


def install(manifest: Path, locked: bool = False, verbose: bool = True) -> None:
    """Resolve and install the environment described by ``manifest``."""
    cmd = [ensure(verbose), "install", "--manifest-path", str(manifest)]
    if locked:
        cmd.append("--locked")
    _run(cmd, verbose=verbose)


def run(
    manifest: Path,
    argv: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    verbose: bool = True,
) -> None:
    """Run ``argv`` inside the environment of ``manifest``.

    ``--frozen`` keeps pixi from re-solving: the environment was installed by
    :func:`install`, and a build must not silently pick up a different stack mid-flight.
    """
    cmd = [ensure(verbose), "run", "--manifest-path", str(manifest), "--frozen", "--", *argv]
    _run(cmd, cwd=cwd, env=env, verbose=verbose)


def shell_hook(manifest: Path, shell: str) -> str:
    """The environment variables that activate ``manifest``'s environment, as shell exports."""
    cmd = [
        ensure(False),
        "shell-hook",
        "--manifest-path",
        str(manifest),
        "--shell",
        shell,
        "--frozen",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise PixiError(f"pixi shell-hook failed: {result.stderr.strip()}")
    return result.stdout


def _run(
    cmd: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    verbose: bool = True,
) -> None:
    if verbose:
        printable = " ".join(str(c) for c in cmd)
        print(f"+ {printable}", flush=True)
    result = subprocess.run(cmd, cwd=None if cwd is None else str(cwd), env=env, check=False)
    if result.returncode != 0:
        raise PixiError(f"command failed (exit {result.returncode}): {' '.join(cmd)}")
