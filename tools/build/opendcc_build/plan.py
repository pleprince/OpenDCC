# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""Turn what OpenUSD was built against into a pixi environment and a set of CMake cache vars.

The rule is the same in both build modes:

  * a dependency OpenUSD carries itself is linked from the USD prefix, so opendcc and USD share
    one copy (and one ABI) of it;
  * a dependency OpenUSD does not carry comes from pixi, pinned to the version VERSIONS.md or the
    USD build recorded -- never to "whatever resolves today";
  * a dependency pixi does not package is built once into the plan's deps prefix.

The version for a pixi dependency is resolved by layering declarations, lowest precedence first:
the `Build platform` table, the `OpenUSD releases` row of the tag being built, and -- when a plan
asks for one -- the `VFX Reference Platform` year. `OpenUSD tested versions` is a floor on the
result: OpenUSD's own VERSIONS.md states what that tag was tested against, and a plan never
resolves a dependency below it without saying so. `--pin` and `--python` override all of it.

Nothing here downloads or builds anything; it produces the derived pixi manifest plus the cache
vars the CMake build is configured with.
"""

from __future__ import annotations

import json
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
    # Import name of a python package the interpreter must be able to load. A conda package that
    # ships an extension module is built per interpreter; this is what the plan verifies.
    python_module: str | None = None


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
    # opendcc's python panels import PySide6; PySide6 and shiboken6 ship in this package and are
    # built per interpreter, so the plan proves they load.
    Dep("pyside", ("pyside6",), python_module="PySide6"),
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
    # Imported by opendcc's python packages (src/python, src/packages): six and Qt.py by the
    # panels/menus, pygments by the script editor, numpy by the bullet physics UI. jinja2 is a
    # pure-python build requirement of usdGenSchema, so it is not import-checked per interpreter.
    Dep("six", ("six",), python_module="six"),
    Dep("pygments", ("pygments",), python_module="pygments"),
    Dep("qt.py", ("qt.py",), python_module="Qt"),
    Dep("numpy", ("numpy",), python_module="numpy"),
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
    # Copies OpenUSD's plugin metadata (lib/usd), its python modules (lib/python/pxr) and the
    # Hydra delegates (plugin/usd) into the install, next to the USD libraries the dependency
    # walk already copies. Without it an install links USD from the build tree while its plugin
    # metadata points there too, and the two copies of libusd_* in one process abort on
    # duplicate TfDebug symbols.
    "DCC_INSTALL_USD": "ON",
    "DCC_INSTALL_QT_PLUGINS": "ON",
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
    vfx: str | None = None  # VFX Reference Platform year this plan resolves against
    from_source: bool = False  # OpenUSD is built by this plan instead of taken from a prefix
    usd_prefix: Path | None = None
    probe: usd_probe.Probe | None = None
    pins: dict[str, str] = field(default_factory=dict)  # dependency -> pixi pin
    providers: dict[str, str] = field(default_factory=dict)  # dependency -> usd|pixi|source|manual
    resolved: dict[str, str] = field(default_factory=dict)  # dependency -> version it stands for
    origins: dict[str, str] = field(default_factory=dict)  # dependency -> what decided the version
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
    vfx: str | None = None,
    python: str | None = None,
    options: dict[str, str] | None = None,
    pin_overrides: dict[str, str] | None = None,
) -> Plan:
    """Resolve everything the build needs into a Plan. Downloads nothing, builds nothing."""
    platform = _platform()
    if release and usd:
        raise PlanError("pass either --usd (an existing OpenUSD build) or --release, not both")
    if vfx and usd:
        raise PlanError(
            "--usd reads the whole dependency stack out of that OpenUSD build; a VFX Reference "
            "Platform year applies to --release, which builds the stack here"
        )

    probe_result = None
    tag = versions_mod.normalize_tag(release) if release else None
    year = versions_mod.normalize_vfx(vfx) if vfx else None
    if year:
        versions.vfx_platform(year)  # name a bad year here, not after the environment exists
    if release:
        # A from-source build has no prefix to read the stack out of: it must be declared.
        versions.release(tag)
        if tag not in versions.tested:
            raise PlanError(
                f"VERSIONS.md has no row for OpenUSD {tag} in 'OpenUSD tested versions'.\n"
                "Copy it from OpenUSD's VERSIONS.md for that tag: a build never resolves below "
                "the versions OpenUSD was tested against."
            )
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
        # The platform year is part of the slug: two plans for one tag can now install two
        # different stacks, and they must not share a tree.
        slug=f"{platform}-usd{tag}"
        + (f"-{year.lower()}" if year else "")
        + ("-src" if release else ""),
        release=tag,
        vfx=year,
        from_source=usd is None,
        usd_prefix=Path(usd).expanduser().resolve() if usd else None,
        probe=probe_result,
        options={**DEFAULT_OPTIONS, **(options or {})},
    )
    plan.compiler_deps = dict(COMPILER_DEPS.get(platform, {}))
    _resolve_dependencies(plan, versions, pin_overrides or {}, python)

    if not plan.usd_prefix:
        # Building OpenUSD from source: there is no prefix yet, everything comes from pixi.
        plan.usd_prefix = plan.usd_dir
    return plan


def _platform() -> str:
    from . import pixi

    return pixi.platform_key()


def _layers(plan: Plan, versions: versions_mod.Versions) -> list[tuple[str, dict[str, str]]]:
    """The declared versions, lowest precedence first.

    Build platform is the highest declared layer on purpose: it holds OpenDCC's own components
    (Qt, PySide, NumPy, the compilers), and a calendar year cannot put the application on a Qt no
    channel publishes. The year replaces what the release row says about the VFX stack, and
    everything it replaces or is held back by is printed by ``_report_platform_overrides``.
    """
    layers: list[tuple[str, dict[str, str]]] = []
    if plan.release in versions.releases:
        layers.append((f"OpenUSD {plan.release} stack", dict(versions.releases[plan.release].pins)))
    if plan.vfx:
        layers.append((plan.vfx, dict(versions.vfx_platform(plan.vfx).pins)))
    layers.append(("Build platform", dict(versions.platform)))
    return layers


def _declared(name: str, layers: list[tuple[str, dict[str, str]]]) -> tuple[str | None, str | None]:
    """The winning declaration for ``name`` and the table it came from."""
    for label, table in reversed(layers):
        if table.get(name):
            return table[name], label
    return None, None


def _parts(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))


def _within(version: str, series: str) -> bool:
    """True when ``version`` lies in the series ``series`` states ('3.6.1' in '3.6')."""
    prefix = _parts(series)
    return _parts(version)[: len(prefix)] == prefix


def _same_series(left: str, right: str) -> bool:
    return _within(left, right) or _within(right, left)


def _gate(
    plan: Plan,
    name: str,
    version: str,
    origin: str,
    tested: dict[str, str],
) -> tuple[str, str]:
    """Apply OpenUSD's tested version for ``name`` as a floor.

    The floor is a minimum, not a replacement: a declaration whose series already admits it
    keeps its series (a pixi series pin resolves to the newest build in it), and only a
    declaration below the tested version is raised. When the raised version comes from the VFX
    platform the two requirements contradict each other and the plan stops instead of quietly
    building off the platform.
    """
    floor = tested.get(name)
    if not floor or _within(floor, version):
        return version, origin
    if _parts(floor) <= _parts(version):
        return version, origin
    if plan.vfx and origin == plan.vfx:
        raise PlanError(
            f"{plan.vfx} pins {name} at {version}, but OpenUSD {plan.release} was tested against "
            f"{floor}, which is a later series.\n"
            f"Pick one: --pin {name}={floor} (off the platform) or a platform year whose "
            f"{name} is at least {floor}."
        )
    plan.warnings.append(
        f"{name}: VERSIONS.md {origin} declares {version}; raised to OpenUSD "
        f"{plan.release}'s tested {floor}"
    )
    return floor, f"OpenUSD {plan.release} tested (floor)"


def _report_platform_overrides(
    plan: Plan,
    layers: list[tuple[str, dict[str, str]]],
    pin_overrides: dict[str, str],
    python_override: str | None,
) -> None:
    """Say what the requested year replaced, and where OpenDCC's own pins held it back."""
    if not plan.vfx:
        return
    index = next(i for i, (label, _) in enumerate(layers) if label == plan.vfx)
    higher, year_pins = layers[index + 1 :], layers[index][1]
    for name, version in year_pins.items():
        if name in pin_overrides:
            plan.warnings.append(
                f"{plan.vfx} pins {name} {version}; --pin overrides it with {pin_overrides[name]}"
            )
            continue
        if name == PYTHON and python_override:
            plan.warnings.append(
                f"{plan.vfx} pins {name} {version}; --python overrides it with {python_override}"
            )
            continue
        declared, where = _declared(name, higher)
        if declared is not None:
            if not _same_series(declared, version):
                plan.warnings.append(
                    f"{plan.vfx} pins {name} {version}; VERSIONS.md {where} holds {declared} and "
                    f"wins (pass --pin {name}={version}.* to move it onto the platform)"
                )
            continue
        declared, where = _declared(name, layers[:index])
        if declared is None or _same_series(declared, version):
            continue
        override = f"--python {declared}" if name == PYTHON else f"--pin {name}={declared}"
        plan.warnings.append(
            f"{plan.vfx} sets {name} {version}; VERSIONS.md {where} declares {declared} "
            f"(pass {override} to keep the local one)"
        )


def _resolve_dependencies(
    plan: Plan,
    versions: versions_mod.Versions,
    pin_overrides: dict[str, str],
    python_override: str | None,
) -> None:
    layers = _layers(plan, versions)
    tested = versions.tested_versions(plan.release) if plan.release else {}
    probe_bundled = plan.probe.bundled if plan.probe else {}
    if plan.probe is not None and not probe_bundled and plan.release in versions.releases:
        # An OpenUSD installation can be built with its dependencies outside its own prefix
        # (that is what `pixi run usd` produces). The probe then reads no versions, and the
        # release row is the only declaration of what that tag was built against.
        plan.warnings.append(
            f"OpenUSD {plan.release} carries no dependency configs of its own; "
            f"its stack is taken from the VERSIONS.md row for {plan.release}"
        )
    _report_platform_overrides(plan, layers, pin_overrides, python_override)
    missing: list[str] = []

    for spec in DEPS:
        if spec.usd_aware and spec.name in probe_bundled:
            plan.providers[spec.name] = "usd"
            plan.resolved[spec.name] = probe_bundled[spec.name]
            plan.origins[spec.name] = "carried by OpenUSD"
            continue

        if spec.pixi is None:
            component = versions.sources.get(spec.name)
            if component is None:
                plan.providers[spec.name] = "manual"
                plan.resolved[spec.name] = "user-supplied"
                continue
            plan.providers[spec.name] = "source"
            plan.resolved[spec.name] = component.version
            plan.origins[spec.name] = "Source-built dependencies"
            continue

        plan.providers[spec.name] = "pixi"
        if spec.name in pin_overrides:
            plan.pins[spec.name] = pin_overrides[spec.name]
            plan.resolved[spec.name] = pin_overrides[spec.name]
            plan.origins[spec.name] = "--pin"
            continue

        version, origin = _declared(spec.name, layers)
        if version is None:
            missing.append(spec.name)
            continue
        version, origin = _gate(plan, spec.name, version, origin, tested)
        plan.pins[spec.name] = _pin(version)
        plan.resolved[spec.name] = version
        plan.origins[spec.name] = origin

    _resolve_python(plan, layers, tested, pin_overrides, python_override)
    _check_bundled_consistency(plan, probe_bundled)
    if missing:
        raise PlanError(
            "VERSIONS.md does not say which version to use for: "
            + ", ".join(sorted(missing))
            + "\nAdd rows to the 'Build platform' table (or pass --pin NAME=VERSION); "
            "the build does not float dependency versions."
        )


def _resolve_python(
    plan: Plan,
    layers: list[tuple[str, dict[str, str]]],
    tested: dict[str, str],
    pin_overrides: dict[str, str],
    python_override: str | None,
) -> None:
    plan.providers[PYTHON] = "pixi"
    if PYTHON in pin_overrides:
        plan.pins[PYTHON] = pin_overrides[PYTHON]
        plan.resolved[PYTHON] = pin_overrides[PYTHON]
        plan.origins[PYTHON] = "--pin"
        return

    if python_override:
        # One interpreter for the OpenUSD build, the environment and opendcc: this is the option
        # that takes python away from the platform without moving anything else.
        plan.pins[PYTHON] = _pin(python_override)
        plan.resolved[PYTHON] = python_override
        plan.origins[PYTHON] = "--python"
        floor = tested.get(PYTHON)
        if floor and _parts(python_override) < _parts(floor):
            plan.warnings.append(
                f"python {python_override} is below OpenUSD {plan.release}'s tested {floor}"
            )
        return

    if plan.probe is not None:
        # The interpreter must be the same one USD's python bindings were built for: opendcc
        # embeds Python and links boost.python/pybind11 modules against that exact ABI.
        if not plan.probe.python:
            raise PlanError("the OpenUSD build does not record its Python version")
        plan.pins[PYTHON] = _pin(plan.probe.python)
        plan.resolved[PYTHON] = plan.probe.python
        plan.origins[PYTHON] = "carried by OpenUSD"
        return

    version, origin = _declared(PYTHON, layers)
    if not version:
        raise PlanError("VERSIONS.md does not say which Python to build OpenUSD with")
    version, origin = _gate(plan, PYTHON, version, origin, tested)
    plan.pins[PYTHON] = _pin(version)
    plan.resolved[PYTHON] = version
    plan.origins[PYTHON] = origin


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
    ]
    if plan.vfx:
        lines.append(
            f"# VFX platform {plan.vfx} (floored by OpenUSD {plan.release}'s tested versions)"
        )
    lines += [
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
            # Quoted keys: a package name may contain a dot ("qt.py"), which an unquoted TOML
            # key would read as a table path.
            lines.append(f'"{package}" = "{plan.pins[name]}"')
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


def installed_metadata(prefix: Path) -> dict[str, dict]:
    """Read the conda records pixi installed: package name -> the record (version, depends, ...)."""
    meta = prefix / "conda-meta"
    out: dict[str, dict] = {}
    if not meta.is_dir():
        return out
    for entry in sorted(meta.glob("*.json")):
        try:
            data = json.loads(entry.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        name, version = data.get("name"), data.get("version")
        if not name or not version:
            # filenames are <name>-<version>-<build>.json
            parts = entry.name[: -len(".json")].rsplit("-", 2)
            if len(parts) != 3:
                continue
            name, version = name or parts[0], version or parts[1]
        out[str(name)] = {**data, "name": name, "version": version}
    return out


def installed_versions(prefix: Path) -> dict[str, str]:
    """Read the versions pixi installed, from the environment's conda metadata."""
    return {
        name: str(record.get("version", "")) for name, record in installed_metadata(prefix).items()
    }


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
        # Checked by cmake/defaults/PythonVersion.cmake: configuring against another interpreter
        # builds shiboken bindings for one python and embeds another.
        "DCC_EXPECTED_PYTHON_VERSION": plan.resolved.get(PYTHON, ""),
    }
    if not plan.platform.startswith("win"):
        # The install is not self-contained: its libraries sit next to the binaries and OpenUSD,
        # the source-built dependencies and the environment live outside it. Without an rpath the
        # installed binaries only run through opendcc-env.sh; with it they run on their own.
        cache["CMAKE_INSTALL_RPATH"] = "@loader_path/../lib;@loader_path/../plugin/usd" if plan.platform.startswith("osx") else "$ORIGIN/../lib;$ORIGIN/../plugin/usd"
        cache["CMAKE_INSTALL_RPATH_USE_LINK_PATH"] = "ON"
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


def python_dependency_rows(plan: Plan) -> list[tuple[str, str, str, str, str, str]]:
    """(dependency, module, package, built for, interpreter, status) for the python packages.

    A conda package that ships an extension module (`python_abi`) is built for one interpreter
    series, and the environment's interpreter is the one opendcc embeds -- a different series is
    not a warning. A noarch package states only a minimum python; that is checked as a floor.
    """
    records = installed_metadata(plan.env_prefix)
    interpreter = str(records.get(PYTHON, {}).get("version", ""))
    if not interpreter:
        return []
    series = ".".join(interpreter.split(".")[:2])
    rows: list[tuple[str, str, str, str, str, str]] = []
    for spec in DEPS:
        if not spec.python_module:
            continue
        package = (spec.pixi or ("",))[0]
        record = records.get(package)
        requirement = _python_requirement(record)
        if record is None:
            built_for, status = "any", "missing"
        elif requirement is None:
            built_for, status = "any", "ok"
        else:
            kind, wanted = requirement
            if kind == "abi":
                built_for = wanted
                status = "ok" if wanted == series else "mismatch"
            else:
                built_for = f">={wanted}"
                status = "ok" if _parts(interpreter) >= _parts(wanted) else "mismatch"
        rows.append((spec.name, spec.python_module, package, built_for, series, status))
    return rows


def _python_requirement(record: dict | None) -> tuple[str, str] | None:
    """('abi', series) for a compiled package, ('min', series) for a noarch one."""
    if not record:
        return None
    for entry in record.get("depends", []):
        fields = entry.split()
        if fields[:1] == ["python_abi"] and len(fields) > 1:
            return ("abi", fields[1].rstrip(".*"))
    for entry in record.get("depends", []):
        match = re.match(r"python\s+>=\s*(\d+\.\d+)", entry)
        if match:
            return ("min", match.group(1))
    return None


def check_python_imports(plan: Plan, modules: list[str]) -> None:
    """Run the plan's interpreter on ``import <module>`` for each and fail with its error."""
    if not modules or not plan.env_prefix.is_dir():
        return
    from . import pixi

    script = "\n".join(f"import {module}" for module in modules)
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
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode == 0:
        return
    detail = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
    raise PlanError(
        f"the environment's interpreter ({plan.python}) cannot import every python dependency "
        f"this plan pins ({', '.join(modules)}):\n{detail}\n"
        "The environment was built for another Python: run `pixi run plan` again, or pass "
        "--python with a version these packages are published for."
    )


def check_python_packages(plan: Plan) -> None:
    """Prove the environment's python carries what opendcc imports, at the right ABI."""
    mismatched = [row for row in python_dependency_rows(plan) if row[5] == "mismatch"]
    if mismatched:
        listing = "; ".join(
            f"{row[2]} was built for Python {row[3]}, the environment has {row[4]}"
            for row in mismatched
        )
        raise PlanError(
            f"the environment's python packages do not match its interpreter: {listing}"
        )
    check_python_imports(plan, [spec.python_module for spec in DEPS if spec.python_module])


def describe(plan: Plan) -> list[tuple[str, str, str, str, str]]:
    """Rows of (dependency, provider, version, origin, resolution) for the plan report."""
    rows: list[tuple[str, str, str, str, str]] = []
    for spec in DEPS:
        provider = plan.providers.get(spec.name, "manual")
        origin = {
            "usd": f"{plan.usd_prefix}",
            "pixi": "pixi:" + ",".join(spec.pixi or ()),
            "source": f"{plan.deps_prefix}",
            "manual": "supplied by the user",
        }.get(provider, provider)
        rows.append(
            (
                spec.name,
                provider,
                plan.resolved.get(spec.name, "-"),
                origin,
                plan.origins.get(spec.name, "-"),
            )
        )
    rows.append(
        (
            PYTHON,
            "pixi",
            plan.resolved.get(PYTHON, "-"),
            "pixi:python",
            plan.origins.get(PYTHON, "-"),
        )
    )
    return rows
