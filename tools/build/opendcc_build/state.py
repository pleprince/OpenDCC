# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""The plan of an already-provisioned build, so later commands need no arguments.

`pixi run plan` writes build/<slug>/state.json; `configure`, `build`, `install` and `test` read
it. Keeping it on disk also documents what a build tree was made from.
"""

from __future__ import annotations

import json
from pathlib import Path

from .plan import Plan
from .probe import Probe


class StateError(RuntimeError):
    pass


def save(plan: Plan) -> Path:
    payload = {
        "schema": 1,
        "slug": plan.slug,
        "platform": plan.platform,
        "release": plan.release,
        "from_source": plan.from_source,
        "usd_prefix": str(plan.usd_prefix) if plan.usd_prefix else None,
        "pins": plan.pins,
        "providers": plan.providers,
        "resolved": plan.resolved,
        "compiler_deps": plan.compiler_deps,
        "options": plan.options,
        "warnings": plan.warnings,
        "probe": plan.probe.to_json() if plan.probe else None,
    }
    plan.build_dir.mkdir(parents=True, exist_ok=True)
    plan.state_file.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return plan.state_file


def load(path: Path) -> tuple[Plan, Path]:
    """Load a plan from a state file or from a build directory containing one."""
    # Resolve first: every prefix the plan derives hangs off this path, and a relative one would
    # end up in the generated environment script and in the CMake cache.
    state_file = Path(path).expanduser().resolve()
    if state_file.is_dir():
        state_file = state_file / "state.json"
    if not state_file.is_file():
        raise StateError(
            f"no build state at {state_file}; run `pixi run plan -- --usd <OpenUSD prefix>` "
            "or `pixi run all -- --release <tag>` first"
        )
    data = json.loads(state_file.read_text())
    root = state_file.parent.parent.parent  # build/<slug>/state.json
    plan = Plan(
        root=root,
        platform=data["platform"],
        slug=data["slug"],
        release=data.get("release"),
        from_source=bool(data.get("from_source")),
        usd_prefix=Path(data["usd_prefix"]) if data.get("usd_prefix") else None,
        probe=_probe_from_json(data.get("probe")),
        pins=dict(data.get("pins", {})),
        providers=dict(data.get("providers", {})),
        resolved=dict(data.get("resolved", {})),
        compiler_deps=dict(data.get("compiler_deps", {})),
        options=dict(data.get("options", {})),
        warnings=list(data.get("warnings", [])),
    )
    return plan, state_file


def _probe_from_json(data: dict | None) -> Probe | None:
    if not data:
        return None
    return Probe(
        prefix=Path(data["prefix"]),
        version=data["version"],
        pxr_version=data["pxr_version"],
        python=data.get("python"),
        python_executable=(
            Path(data["python_executable"]) if data.get("python_executable") else None
        ),
        bundled=dict(data.get("bundled", {})),
        bundled_libs=set(data.get("bundled", {})),
        libs=set(data.get("libs", [])),
        internal_boost_python=bool(data.get("internal_boost_python")),
        has_python_bindings=bool(data.get("has_python_bindings")),
        lib_prefix=data.get("lib_prefix", "lib"),
        cmake_config=Path(data["cmake_config"]) if data.get("cmake_config") else None,
    )


def find(root: Path) -> Path:
    """Pick the build state when the caller did not name one.

    A single build tree is unambiguous; several are an error that lists them, because guessing
    which OpenUSD a build was made against is not something a build system should do.
    """
    build = Path(root) / "build"
    states = sorted(build.glob("*/state.json")) if build.is_dir() else []
    if not states:
        raise StateError(
            "no configured build found under build/; run `pixi run plan -- --usd <OpenUSD "
            "prefix>` or `pixi run all -- --release <tag>`"
        )
    if len(states) > 1:
        names = ", ".join(state.parent.name for state in states)
        raise StateError(f"several builds exist ({names}); pass --build <slug>")
    return states[0]
