# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""Turn what OpenUSD was built against into a pixi environment and a set of CMake cache vars.

The rule is the same in both build modes:

  * a dependency OpenUSD carries itself is linked from the USD prefix, so opendcc and USD share
    one copy (and one ABI) of it;
  * a dependency OpenUSD does not carry comes from pixi, pinned to the version VERSIONS.md or the
    USD build recorded -- never to "whatever resolves today";
  * a dependency pixi does not package is built once into the plan's deps prefix.

Nothing here downloads or builds anything; it produces the derived pixi manifest plus the cache
vars the CMake build is configured with.
"""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from . import probe as usd_probe
from . import versions as versions_mod

# anderslanglands publishes the VFX stack (OpenImageIO, OpenColorIO, MaterialX, OSL, OpenUSD)
# built against each other; conda-forge carries Qt, boost, the compilers and everything else.
# Strict priority keeps a VFX library from being answered by whichever channel happens to have a
# newer build of it.
CHANNELS = ("https://conda.anaconda.org/anderslanglands", "conda-forge")


@dataclass(frozen=True)
class Dep:
    """One third-party dependency of the opendcc build."""

    name: str
    pixi: tuple[str, ...] | None  # pixi packages; None when the build produces it (source)
    cmake_vars: tuple[str, ...] = ()
    usd_aware: bool = False  # a copy inside the OpenUSD prefix can satisfy it
    abi_critical: bool = False  # must be the same build as USD's, not merely the same version


DEPS: tuple[Dep, ...] = (
    # USD itself and its own dependency set.
    Dep("boost", ("libboost-devel",), ("BOOST_ROOT",), usd_aware=True, abi_critical=True),
    Dep("tbb", ("tbb-devel",), ("TBB_ROOT_DIR",), usd_aware=True, abi_critical=True),
    # imath/openexr/materialx/eigen/doctest are found in config mode, so the prefix order
    # of CMAKE_PREFIX_PATH places them; only module-mode finders need a hint.
    Dep("imath", ("imath",), (), usd_aware=True, abi_critical=True),
    Dep("openexr", ("openexr",), (), usd_aware=True, abi_critical=True),
    Dep("openimageio", ("openimageio",), ("OIIO_LOCATION",), usd_aware=True, abi_critical=True),
    Dep("opencolorio", ("opencolorio",), ("OCIO_LOCATION",), usd_aware=True, abi_critical=True),
    # OpenUSD's hdSt links OpenSubdiv::osdGPU whenever GPU support is on, which is the only mode
    # that gives opendcc a render delegate. The plain package is the CPU-only build and makes
    # OpenUSD's configure fail on the missing osdGPU target; the GPU build is a separate package.
    Dep("opensubdiv", ("opensubdiv-gpu",), ("OPENSUBDIV_DIR",), usd_aware=True, abi_critical=True),
    # materialx-dev carries the code generators only; hdSt also includes MaterialXRender/Util.h,
    # which ships as a separate package that depends on the matching materialx-dev build.
    Dep("materialx", ("materialx", "materialx-render"), (), usd_aware=True),
    Dep("openshadinglanguage", ("openshadinglanguage",), ("OSL_ROOT",)),
    # Toolchain and opendcc-only dependencies.
    Dep("qt", ("qt6-main", "qt6-multimedia"), cmake_vars=()),
    Dep("pyside", ("pyside6",)),
    Dep("pybind11", ("pybind11",)),
    Dep("libclang", ("libclang",), ("SHIBOKEN_CLANG_INSTALL_DIR",)),
    Dep("glew", ("glew",), ("GLEW_LOCATION",)),
    Dep("zeromq", ("zeromq",), ("ZMQ_ROOT",)),
    Dep("eigen", ("eigen",)),
    Dep("graphviz", ("graphviz",), ("GRAPHVIZ_ROOT",)),
    Dep("doctest", ("doctest",)),
    # spdlog is compiled against this fmt instead of its bundled copy, matching the fmt
    # OpenImageIO vendors (see VERSIONS.md).
    Dep("fmt", ("fmt",)),
    # opendcc's own find_package(Embree 3) wants embree3/rtcore.h; OpenUSD's hdEmbree plugin
    # wants Embree 4. Both packages live side by side under different sonames.
    Dep("embree", ("embree3",), ("EMBREE_LOCATION",)),
    Dep("embree4", ("embree",), (), usd_aware=True),
    Dep("bullet", ("bullet-cpp",), ("BULLET_ROOT",)),
    Dep("cmake", ("cmake",)),
    Dep("ninja", ("ninja",)),
    # Imported by OpenUSD's usdGenSchema, which the build runs with this environment's python.
    Dep("jinja2", ("jinja2",)),
    # Built from source into the plan's deps prefix (see VERSIONS.md, Source-built dependencies).
    Dep("qtads", None),
    Dep("sentry", None),
    Dep("openmesh", None, ("OPENMESH_ROOT",)),
    Dep("libigl", None, ("IGL_ROOT",)),
)

PYTHON = "python"

# Compilers pixi provides where the platform has no default toolchain. macOS uses the Xcode CLT
# clang and Windows the Visual Studio one: a distro compiler or a different SDK than the one Qt
# and OpenUSD were built with is the usual source of "works on my machine".
COMPILER_DEPS = {
    "linux-64": {"gcc_linux-64": "14.*", "gxx_linux-64": "14.*"},
    "linux-aarch64": {"gcc_linux-aarch64": "14.*", "gxx_linux-aarch64": "14.*"},
}

DEFAULT_OPTIONS = {
    "CMAKE_BUILD_TYPE": "Release",
    "DCC_BUILD_TESTS": "ON",
    "DCC_TESTS_GUI": "OFF",
    "DCC_TESTS_USD_RENDER": "OFF",
    "DCC_PYSIDE_CMAKE_FIND": "ON",
    "DCC_BUILD_ARNOLD_SUPPORT": "OFF",
    "DCC_USD_FALLBACK_PROXY_BUILD_ARNOLD_USD": "OFF",
    "DCC_BUILD_RENDERMAN_SUPPORT": "OFF",
    "DCC_BUILD_CYCLES_SUPPORT": "OFF",
    "DCC_USD_FALLBACK_PROXY_BUILD_CYCLES": "OFF",
    "DCC_USD_FALLBACK_PROXY_BUILD_MOONRAY": "OFF",
    "DCC_USE_PTEX": "OFF",
    "DCC_HOUDINI_SUPPORT": "OFF",
    "DCC_KATANA_SUPPORT": "OFF",
    "DCC_BUILD_CRASH_REPORTER": "OFF",
    "DCC_BUILD_HYDRA_OP": "OFF",
    "DCC_BUILD_EDITORIAL": "OFF",
    "DCC_BUILD_ANIM_ENGINE": "ON",
    "DCC_BUILD_EXPRESSIONS_ENGINE": "ON",
    "DCC_BUILD_RENDER_VIEW": "ON",
    "DCC_NODE_EDITOR": "ON",
    "DCC_BUILD_BULLET_PHYSICS": "ON",
    # Installs sentry_crashpad::crashpad_handler, which only exists in a sentry-native built
    # with SENTRY_BACKEND=crashpad. The pinned source build is backend-less (no channel
    # publishes a crashpad one), so the handler is not there to install.
    "DCC_INSTALL_SENTRY": "OFF",
    "DCC_USE_PYTHON_3": "ON",
    # OFF keeps the application from pointing PYTHONHOME at the install prefix: this install has
    # no bundled standard library, it runs on the interpreter of the build environment (see
    # BUILDING.md). A redistributable build sets this and DCC_INSTALL_PYTHON together.
    "DCC_EMBEDDED_PYTHON_HOME": "OFF",
    "CMAKE_EXPORT_COMPILE_COMMANDS": "ON",
}


class PlanError(RuntimeError):
    pass


@dataclass
class Plan:
    root: Path
    platform: str
    slug: str
    release: str | None = None
    from_source: bool = False  # OpenUSD is built by this plan instead of taken from a prefix
    usd_prefix: Path | None = None
    probe: usd_probe.Probe | None = None
    pins: dict[str, str] = field(default_factory=dict)  # dependency -> pixi pin
    providers: dict[str, str] = field(default_factory=dict)  # dependency -> usd|pixi|source|manual
    resolved: dict[str, str] = field(default_factory=dict)  # dependency -> version it stands for
    compiler_deps: dict[str, str] = field(default_factory=dict)
    options: dict[str, str] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)

    @property
    def manifest(self) -> Path:
        return self.env_dir / "pixi.toml"

    @property
    def env_dir(self) -> Path:
        return self.build_dir / "env"

    @property
    def env_prefix(self) -> Path:
        return self.env_dir / ".pixi" / "envs" / "default"

    @property
    def env_cmake_prefix(self) -> Path:
        """CMake prefix of the pixi environment: a Windows conda environment keeps
        include/, lib/ and bin/ under Library/, so the root is not a prefix CMake knows."""
        return self.env_prefix / "Library" if self.platform.startswith("win") else self.env_prefix

    @property
    def deps_prefix(self) -> Path:
        return self.build_dir / "deps"

    @property
    def build_dir(self) -> Path:
        return self.root / "build" / self.slug

    @property
    def cmake_dir(self) -> Path:
        return self.build_dir / "cmake"

    @property
    def usd_dir(self) -> Path:
        return self.build_dir / "usd"

    @property
    def install_dir(self) -> Path:
        return self.root / "install_dir" / self.slug

    @property
    def state_file(self) -> Path:
        return self.build_dir / "state.json"

    @property
    def python(self) -> Path:
        suffix = ".exe" if self.platform.startswith("win") else ""
        return self.env_prefix / (f"python{suffix}" if suffix else "bin/python")

    def source(self, name: str, versions: versions_mod.Versions) -> versions_mod.SourceComponent:
        component = versions.sources.get(name)
        if component is None:
            raise PlanError(f"VERSIONS.md has no 'Source-built dependencies' row for {name}")
        return component


def make_plan(
    root: Path,
    versions: versions_mod.Versions,
    *,
    usd: Path | None = None,
    release: str | None = None,
    options: dict[str, str] | None = None,
    pin_overrides: dict[str, str] | None = None,
) -> Plan:
    """Resolve everything the build needs into a Plan. Downloads nothing, builds nothing."""
    platform = _platform()
    if release and usd:
        raise PlanError("pass either --usd (an existing OpenUSD build) or --release, not both")

    probe_result = None
    tag = versions_mod.normalize_tag(release) if release else None
    if usd is not None:
        probe_result = usd_probe.probe(Path(usd))
        problems = usd_probe.validate(probe_result)
        if problems:
            raise PlanError("cannot build against this OpenUSD:\n  - " + "\n  - ".join(problems))
        tag = versions_mod.normalize_tag(probe_result.version)

    if tag is None:
        raise PlanError("pass --usd (an existing OpenUSD build) or --release (an OpenUSD tag)")

    plan = Plan(
        root=Path(root),
        platform=platform,
        slug=f"{platform}-usd{tag}" + ("-src" if release else ""),
        release=tag,
        from_source=usd is None,
        usd_prefix=Path(usd).expanduser().resolve() if usd else None,
        probe=probe_result,
        options={**DEFAULT_OPTIONS, **(options or {})},
    )
    plan.compiler_deps = dict(COMPILER_DEPS.get(platform, {}))
    _resolve_dependencies(plan, versions, pin_overrides or {})

    if not plan.usd_prefix:
        # Building OpenUSD from source: there is no prefix yet, everything comes from pixi.
        plan.usd_prefix = plan.usd_dir
    return plan


def _platform() -> str:
    from . import pixi

    return pixi.platform_key()


def _resolve_dependencies(
    plan: Plan, versions: versions_mod.Versions, pin_overrides: dict[str, str]
) -> None:
    base = dict(versions.platform)
    probe_bundled = plan.probe.bundled if plan.probe else {}
    if plan.from_source:
        # The release row describes the stack we are about to build OpenUSD against.
        base.update(versions.release(plan.release).pins)
    elif not probe_bundled and plan.release in versions.releases:
        # An OpenUSD installation can be built with its dependencies outside its own prefix
        # (that is what `pixi run usd` produces). The probe then reads no versions, and the
        # release row is the only declaration of what that tag was built against.
        base.update(versions.releases[plan.release].pins)
        plan.warnings.append(
            f"OpenUSD {plan.release} carries no dependency configs of its own; "
            f"its stack is taken from the VERSIONS.md row for {plan.release}"
        )
    missing: list[str] = []

    for spec in DEPS:
        if spec.usd_aware and spec.name in probe_bundled:
            plan.providers[spec.name] = "usd"
            plan.resolved[spec.name] = probe_bundled[spec.name]
            continue

        if spec.pixi is None:
            component = versions.sources.get(spec.name)
            if component is None:
                plan.providers[spec.name] = "manual"
                plan.resolved[spec.name] = "user-supplied"
                continue
            plan.providers[spec.name] = "source"
            plan.resolved[spec.name] = component.version
            continue

        plan.providers[spec.name] = "pixi"
        if spec.name in pin_overrides:
            plan.pins[spec.name] = pin_overrides[spec.name]
            plan.resolved[spec.name] = pin_overrides[spec.name]
        elif base.get(spec.name):
            plan.pins[spec.name] = _pin(base[spec.name])
            plan.resolved[spec.name] = base[spec.name]
        else:
            missing.append(spec.name)

    _resolve_python(plan, versions, pin_overrides)
    _check_bundled_consistency(plan, probe_bundled)
    if missing:
        raise PlanError(
            "VERSIONS.md does not say which version to use for: "
            + ", ".join(sorted(missing))
            + "\nAdd rows to the 'Build platform' table (or pass --pin NAME=VERSION); "
            "the build does not float dependency versions."
        )


def _resolve_python(
    plan: Plan, versions: versions_mod.Versions, pin_overrides: dict[str, str]
) -> None:
    plan.providers[PYTHON] = "pixi"
    if PYTHON in pin_overrides:
        plan.pins[PYTHON] = pin_overrides[PYTHON]
        plan.resolved[PYTHON] = pin_overrides[PYTHON]
        return

    if plan.probe is not None:
        # The interpreter must be the same one USD's python bindings were built for: opendcc
        # embeds Python and links boost.python/pybind11 modules against that exact ABI.
        if not plan.probe.python:
            raise PlanError("the OpenUSD build does not record its Python version")
        plan.pins[PYTHON] = _pin(plan.probe.python)
        plan.resolved[PYTHON] = plan.probe.python
        return

    version = versions.platform.get(PYTHON)
    if version is None and plan.from_source:
        version = versions.release(plan.release).pins.get(PYTHON)
    if not version:
        raise PlanError("VERSIONS.md does not say which Python to build OpenUSD with")
    plan.pins[PYTHON] = _pin(version)
    plan.resolved[PYTHON] = version


def _check_bundled_consistency(plan: Plan, probe_bundled: dict[str, str]) -> None:
    """USD carries these, so opendcc must not also pull a different copy from pixi."""
    if plan.probe is None:
        return
    for name, version in probe_bundled.items():
        if name == "boost" and plan.probe.internal_boost_python:
            continue
        if name in ("embree", "embree4", "ptex", "openvdb", "alembic"):
            continue  # not ABI-shared with opendcc, or optional and off
        if name not in plan.providers:
            plan.warnings.append(
                f"OpenUSD carries {name} {version}; opendcc links USD's copy "
                f"({plan.usd_prefix})"
            )


def _pin(version: str) -> str:
    """VERSIONS.md states a version; pixi wants a spec.

    "3.12" -> "3.12.*", "2021.13" -> "2021.13.*", "6.11" -> "6.11.*"; a fully qualified
    version such as "3.11.15" is pinned exactly, because that is what an ABI needs.
    """
    version = version.strip()
    if version.endswith("*"):
        return version
    parts = version.split(".")
    if re.match(r"^\d+(\.\d+)+$", version) and len(parts) >= 3:
        return "==" + version
    return version + ".*"


# --------------------------------------------------------------------------------------------
# generated pixi manifest


def render_manifest(plan: Plan) -> str:
    lines = [
        "# Generated by tools/build/opendcc-build. Do not edit: edit VERSIONS.md (or pass --pin)",
        "# and run `pixi run plan` again.",
        "#",
        f"# platform     {plan.platform}",
        f"# OpenUSD      {plan.release}"
        + (f" at {plan.usd_prefix}" if plan.probe else " (built from source)")
        + (f" / python {plan.probe.python}" if plan.probe and plan.probe.python else ""),
        "",
        "[workspace]",
        "channels = [" + ", ".join(f'"{c}"' for c in CHANNELS) + "]",
        f'platforms = ["{plan.platform}"]',
        'channel-priority = "strict"',
        "",
        "[dependencies]",
    ]
    for name in sorted(plan.pins):
        for package in _pixi_packages(name):
            lines.append(f'{package} = "{plan.pins[name]}"')
    if plan.compiler_deps:
        lines.append("")
        lines.append(f"[target.{plan.platform}.dependencies]")
        for package, pin in sorted(plan.compiler_deps.items()):
            lines.append(f'{package} = "{pin}"')
    lines.append("")
    return "\n".join(lines)


def _pixi_packages(dep_name: str) -> tuple[str, ...]:
    for spec in DEPS:
        if spec.name == dep_name:
            if not spec.pixi:
                raise PlanError(f"{dep_name} is not provided by pixi")
            return spec.pixi
    if dep_name == PYTHON:
        return ("python",)
    raise PlanError(f"unknown dependency {dep_name!r}")


# --------------------------------------------------------------------------------------------
# environment verification: what the environment actually installed


def installed_versions(prefix: Path) -> dict[str, str]:
    """Read the versions pixi installed, from the environment's conda metadata."""
    meta = prefix / "conda-meta"
    out: dict[str, str] = {}
    if not meta.is_dir():
        return out
    for entry in sorted(meta.glob("*.json")):
        # filenames are <name>-<version>-<build>.json
        stem = entry.name[: -len(".json")]
        parts = stem.rsplit("-", 2)
        if len(parts) != 3:
            continue
        out[parts[0]] = parts[1]
    return out


def verify(plan: Plan) -> list[tuple[str, str, str, str, str]]:
    """Compare the probed/release versions with what pixi actually installed.

    Returns rows of (dependency, provider, wanted, installed, status) where status is
    "ok", "drift" (different patch, same major.minor) or "mismatch".
    """
    installed = installed_versions(plan.env_prefix)
    rows: list[tuple[str, str, str, str, str]] = []
    for spec in DEPS + (Dep(PYTHON, ("python",)),):
        provider = plan.providers.get(spec.name, "manual")
        if provider != "pixi" or not spec.pixi:
            continue
        package = spec.pixi[0]
        have = installed.get(package)
        if have is None:
            # meta packages (pyside6 pulls qt6-main, ...) may not be installed themselves
            have = _transitive(installed, package)
        wanted = plan.resolved.get(spec.name, "")
        rows.append((spec.name, provider, wanted, have or "-", _status(wanted, have)))
    return rows


def _transitive(installed: dict[str, str], package: str) -> str | None:
    aliases = {
        "libboost-devel": "libboost",
        "tbb-devel": "tbb",
        "qt6-main": "qt6-main",
        "pyside6": "pyside6",
        "bullet-cpp": "bullet",
    }
    return installed.get(aliases.get(package, package))


def _status(wanted: str, have: str | None) -> str:
    if have is None:
        return "missing"
    wanted = wanted.strip().rstrip(".*").rstrip(".")
    if not wanted or wanted in ("unpinned", "user-supplied"):
        return "ok"
    want_parts = wanted.split(".")
    have_parts = have.split(".")
    if have_parts[: len(want_parts)] == want_parts:
        return "ok"
    if want_parts[:2] == have_parts[:2]:
        return "drift"
    return "mismatch"


# --------------------------------------------------------------------------------------------
# CMake cache variables for the opendcc build


def cmake_cache(plan: Plan) -> dict[str, str]:
    cache: dict[str, str] = {
        "CMAKE_BUILD_TYPE": plan.options.get("CMAKE_BUILD_TYPE", "Release"),
        "CMAKE_INSTALL_PREFIX": str(plan.install_dir),
        "CMAKE_EXPORT_COMPILE_COMMANDS": plan.options.get("CMAKE_EXPORT_COMPILE_COMMANDS", "ON"),
        "CMAKE_PREFIX_PATH": ";".join(
            dict.fromkeys(
                [str(plan.usd_prefix), str(plan.deps_prefix), str(plan.env_cmake_prefix)]
            )
        ),
        "USD_ROOT": str(plan.usd_prefix),
        "USD_CONFIG_FILE": str(plan.usd_prefix / "pxrConfig.cmake"),
        "Python3_EXECUTABLE": str(plan.python),
        "PYTHON_EXECUTABLE": str(plan.python),
    }
    if plan.probe is not None and plan.probe.lib_prefix != "lib":
        # find_package(USD) locates <usd>/lib through <prefix>usd<shared suffix>.
        cache["PXR_LIB_PREFIX"] = plan.probe.lib_prefix
    for spec in DEPS:
        provider = plan.providers.get(spec.name)
        prefix = {
            "usd": plan.usd_prefix,
            "pixi": plan.env_cmake_prefix,
            "source": plan.deps_prefix,
        }.get(
            provider or ""
        )
        if prefix is None:
            continue
        for variable in spec.cmake_vars:
            if variable == "IGL_ROOT":
                cache[variable] = str(plan.deps_prefix / "libigl")
            else:
                cache[variable] = str(prefix)

    cache.update({key: value for key, value in plan.options.items() if key.startswith("DCC_")})
    return cache


PYTHON_ABI_PROBE = """
import os
import sys
sys.path.insert(0, {path!r})
# Since Python 3.8 a Windows extension module resolves its dependencies through
# os.add_dll_directory(), not PATH: _tf.pyd cannot find tf.dll without this.
for directory in {dll_dirs!r}:
    if os.path.isdir(directory) and hasattr(os, "add_dll_directory"):
        os.add_dll_directory(directory)
try:
    from pxr import Usd
except Exception as error:
    raise SystemExit("{{}}: {{}}".format(type(error).__name__, error))
"""


def check_python_abi(plan: Plan) -> None:
    """Prove that this environment's interpreter can load the OpenUSD python bindings.

    opendcc embeds Python, and an OpenUSD built with python support links the interpreter it was
    configured with. Two libpython images in one process is a segfault, not a warning, so this is
    checked by importing pxr rather than by comparing version strings.
    """
    if plan.probe is None or not plan.probe.has_python_bindings:
        return
    from . import pixi

    python_path = plan.usd_prefix / "lib" / "python"
    dll_dirs = (
        [str(plan.usd_prefix / "lib"), str(plan.env_cmake_prefix / "bin")]
        if plan.platform.startswith("win")
        else []
    )
    script = PYTHON_ABI_PROBE.format(path=str(python_path), dll_dirs=dll_dirs)
    command = [
        pixi.ensure(False),
        "run",
        "--manifest-path",
        str(plan.manifest),
        "--frozen",
        "--",
        str(plan.python),
        "-c",
        script,
    ]
    env = dict(os.environ)
    if plan.platform.startswith("win"):
        # Windows has no rpath: PATH is what the loader uses for the tools this probe starts.
        env["PATH"] = os.pathsep.join(
            str(prefix) for prefix in (plan.usd_prefix / "lib", plan.env_cmake_prefix / "bin")
        ) + os.pathsep + env.get("PATH", "")
    result = subprocess.run(command, capture_output=True, text=True, env=env, check=False)
    if result.returncode == 0:
        return
    recorded = plan.probe.python_executable or "an unknown interpreter"
    detail = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
    raise PlanError(
        f"this OpenUSD build's python bindings cannot be imported by {plan.python} "
        f"(OpenUSD was built against {recorded}).\n"
        f"{detail}\n"
        "Build OpenUSD with this build system instead, which makes both sides use one "
        f"interpreter: `pixi run all -- --release {plan.release}`."
    ) from None


def describe(plan: Plan) -> list[tuple[str, str, str, str]]:
    """Rows of (dependency, provider, version, origin) for the plan report."""
    rows: list[tuple[str, str, str, str]] = []
    for spec in DEPS:
        provider = plan.providers.get(spec.name, "manual")
        origin = {
            "usd": f"{plan.usd_prefix}",
            "pixi": "pixi:" + ",".join(spec.pixi or ()),
            "source": f"{plan.deps_prefix}",
            "manual": "supplied by the user",
        }.get(provider, provider)
        rows.append((spec.name, provider, plan.resolved.get(spec.name, "-"), origin))
    rows.append((PYTHON, "pixi", plan.resolved.get(PYTHON, "-"), "pixi:python"))
    return rows
