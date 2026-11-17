# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""Inspect an installed OpenUSD build: what it is, what it was built against, what it ships.

This is the "extract dependency versions from that build" half of the build system. Everything
here reads files the USD build already produced (pxr.h, pxrConfig.cmake and the CMake package
configs it installed next to itself); nothing is executed and nothing is guessed. When a fact
cannot be read, the attribute stays None and the planner decides whether that is fatal.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

# CMake package directory name inside <usd>/lib/cmake -> canonical dependency name.
CMAKE_DIR_NAMES = {
    "boost": "boost",
    "imath": "imath",
    "openexr": "openexr",
    "openimageio": "openimageio",
    "opencolorio": "opencolorio",
    "opensubdiv": "opensubdiv",
    "materialx": "materialx",
    "tbb": "tbb",
    "embree": "embree",
    "alembic": "alembic",
    "ptex": "ptex",
    "openvdb": "openvdb",
    "opentimelineio": "opentimelineio",
}

# Libraries USD must have for opendcc to link: the Hydra GL/Storm/Hdx stack, imaging and shading.
REQUIRED_USD_LIBS = (
    "hd",
    "hdSt",
    "hdx",
    "hdsi",
    "glf",
    "hgi",
    "hgiGL",
    "usdImaging",
    "usdImagingGL",
    "usdShade",
    "usdLux",
    "usdGeom",
    "usdSkel",
    "sdr",
    "sdf",
    "pcp",
)


class ProbeError(RuntimeError):
    pass


@dataclass
class Probe:
    prefix: Path
    version: str  # "25.11"
    pxr_version: str  # "0.25.11"
    python: str | None = None  # full version recorded by the USD build, e.g. "3.11.15"
    python_executable: Path | None = None  # the interpreter that build used
    bundled: dict[str, str] = field(default_factory=dict)  # dep -> version USD was built against
    bundled_libs: set[str] = field(default_factory=set)  # canonical dep names present in <usd>/lib
    libs: set[str] = field(default_factory=set)  # pxr libraries this build exports
    internal_boost_python: bool = False
    has_python_bindings: bool = False
    lib_prefix: str = "lib"  # pxr libraries are <lib_prefix>usd, <lib_prefix>usdGeom, ...
    cmake_config: Path | None = None

    @property
    def python_minor(self) -> str | None:
        if not self.python:
            return None
        parts = self.python.split(".")
        return ".".join(parts[:2]) if len(parts) >= 2 else None

    def to_json(self) -> dict:
        return {
            "prefix": str(self.prefix),
            "version": self.version,
            "pxr_version": self.pxr_version,
            "python": self.python,
            "python_executable": str(self.python_executable) if self.python_executable else None,
            "bundled": dict(sorted(self.bundled.items())),
            "libs": sorted(self.libs),
            "internal_boost_python": self.internal_boost_python,
            "has_python_bindings": self.has_python_bindings,
            "lib_prefix": self.lib_prefix,
            "cmake_config": str(self.cmake_config) if self.cmake_config else None,
        }


def probe(usd: Path) -> Probe:
    prefix = _resolve_prefix(Path(usd))
    config = prefix / "pxrConfig.cmake"
    if not config.is_file():
        raise ProbeError(
            f"{prefix} does not look like an installed OpenUSD build: no pxrConfig.cmake.\n"
            "Point --usd at the USD install prefix (the directory containing pxrConfig.cmake)."
        )
    include = prefix / "include"
    pxr_h = include / "pxr" / "pxr.h"
    if not pxr_h.is_file():
        raise ProbeError(f"{prefix} has pxrConfig.cmake but no include/pxr/pxr.h")

    text = config.read_text(encoding="utf-8", errors="replace")
    major, minor, patch = _pxr_version(pxr_h)
    result = Probe(
        prefix=prefix,
        version=f"{minor}.{patch:02d}" if patch else f"{minor}",
        pxr_version=f"{major}.{minor}.{patch}",
        python=_python_version(text, pxr_h),
        python_executable=_python_executable(text),
        internal_boost_python=_internal_boost_python(pxr_h),
        has_python_bindings=(prefix / "lib" / "python" / "pxr" / "__init__.py").is_file(),
        lib_prefix=_lib_prefix(prefix),
        cmake_config=config,
    )
    result.libs = _usd_libs(include)
    result.bundled = _bundled_versions(prefix, include)
    result.bundled_libs = set(result.bundled)
    return result


def _lib_prefix(prefix: Path) -> str:
    """The prefix on pxr library file names: "lib" normally, "libusd_" for some builds.

    find_package(USD) looks for <PXR_LIB_PREFIX>usd<shared suffix> to locate the library
    directory, so a build that renamed its libraries must report this.
    """
    lib = prefix / "lib"
    if not lib.is_dir():
        return "lib"
    suffixes = (".dylib", ".so", ".dll", ".lib")
    stems: set[str] = set()
    for entry in lib.iterdir():
        name = entry.name
        for suffix in suffixes:
            if name.endswith(suffix):
                stems.add(name[: -len(suffix)])
                break
        if ".so." in name:
            stems.add(name.split(".so.")[0])
    candidates = {stem[: -len("usd")] for stem in stems if stem.endswith("usd")}
    for candidate in sorted(candidates, key=len):
        if any(f"{candidate}usdGeom{suffix}" in {e.name for e in lib.iterdir()} for suffix in suffixes):
            return candidate
    return "lib"


def _resolve_prefix(path: Path) -> Path:
    path = path.expanduser().resolve()
    if path.is_file() and path.name == "pxrConfig.cmake":
        return path.parent
    return path


def _pxr_version(pxr_h: Path) -> tuple[int, int, int]:
    text = pxr_h.read_text(encoding="utf-8", errors="replace")

    def grab(name: str) -> int:
        m = re.search(rf"#define\s+{name}\s+(\d+)", text)
        return int(m.group(1)) if m else 0

    return grab("PXR_MAJOR_VERSION"), grab("PXR_MINOR_VERSION"), grab("PXR_PATCH_VERSION")


def _python_executable(config_text: str) -> Path | None:
    m = re.search(r"Python3_EXECUTABLE\s+\[\[([^\]]+)\]\]", config_text)
    return Path(m.group(1)) if m else None


def _python_version(config_text: str, pxr_h: Path) -> str | None:
    # pxrConfig.cmake pins the Python it was configured with:
    #   find_dependency(Python3 "3.11.15" EXACT COMPONENTS Development)
    m = re.search(r'find_dependency\(\s*Python3\s+"?([\d.]+)"?', config_text)
    if m:
        return m.group(1)
    # ... and records the interpreter/library paths it used.
    for pattern in (
        r"Python3_EXECUTABLE\s+\[\[([^\]]+)\]\]",
        r"Python3_LIBRARY\s+\[\[([^\]]+)\]\]",
    ):
        m = re.search(pattern, config_text)
        if m:
            found = re.search(r"python(\d+\.\d+)", m.group(1), re.IGNORECASE)
            if found:
                return found.group(1)
    return None


def _internal_boost_python(pxr_h: Path) -> bool:
    text = pxr_h.read_text(encoding="utf-8", errors="replace")
    if not re.search(r"#define\s+PXR_USE_INTERNAL_BOOST_PYTHON", text):
        return False
    # A '#if 0'-guarded define means the build links a real boost.python.
    return not re.search(
        r"#if\s+0\s*\n\s*#define\s+PXR_USE_INTERNAL_BOOST_PYTHON", text
    )


def _usd_libs(include: Path) -> set[str]:
    """The pxr libraries this build installed.

    Read from the include tree rather than pxrConfig.cmake: that file only lists a library name
    such as "usd_m" for a monolithic build, while the headers are grouped by the same set of
    library names in every layout USD has shipped (pxr/<lib>, pxr/imaging/<lib>, pxr/usd/<lib>).
    """
    root = include / "pxr"
    if not root.is_dir():
        return set()
    libs: set[str] = set()
    for group in [root, *sorted(entry for entry in root.iterdir() if entry.is_dir())]:
        for child in group.iterdir():
            if child.is_dir():
                libs.add(child.name)
    return libs


def _bundled_versions(prefix: Path, include: Path) -> dict[str, str]:
    """Dependency versions this USD build carries, from its CMake configs and headers."""
    versions: dict[str, str] = {}
    cmake_root = prefix / "lib" / "cmake"
    if cmake_root.is_dir():
        for package_dir in sorted(cmake_root.iterdir()):
            if not package_dir.is_dir():
                continue
            name = CMAKE_DIR_NAMES.get(package_dir.name.split("-")[0].lower())
            if not name:
                continue
            version = _config_version(package_dir)
            if version:
                versions[name] = version
    for name, version in _header_versions(include).items():
        versions.setdefault(name, version)
    return versions


def _config_version(package_dir: Path) -> str | None:
    for entry in sorted(package_dir.glob("*ConfigVersion.cmake")):
        m = re.search(
            r'set\(\s*PACKAGE_VERSION\s+"?([0-9][0-9.]*)"?', entry.read_text(errors="replace")
        )
        if m:
            return m.group(1)
    return None


def _header_versions(include: Path) -> dict[str, str]:
    """Versions for dependencies whose install ships headers but no CMake package config."""
    probes = {
        "boost": (include / "boost" / "version.hpp", r'#define\s+BOOST_LIB_VERSION\s+"(\d+)_(\d+)"'),
        "imath": (include / "Imath" / "ImathConfig.h", r'#define\s+IMATH_VERSION_STRING\s+"([\d.]+)"'),
        "openexr": (
            include / "OpenEXR" / "OpenEXRConfig.h",
            r'#define\s+OPENEXR_VERSION_STRING\s+"([\d.]+)"',
        ),
        "openimageio": (
            include / "OpenImageIO" / "oiioversion.h",
            r"#define\s+OIIO_VERSION_STRING\s+\"([\d.]+)\"",
        ),
    }
    out: dict[str, str] = {}
    for name, (path, pattern) in probes.items():
        if not path.is_file():
            continue
        m = re.search(pattern, path.read_text(errors="replace"))
        if not m:
            continue
        out[name] = ".".join(g for g in m.groups()) if len(m.groups()) > 1 else m.group(1)
    out.update(_tbb_version(include, out))
    out.update(_opensubdiv_version(include, out))
    return out


def _tbb_version(include: Path, _known: dict[str, str]) -> dict[str, str]:
    for relative in ("oneapi/tbb/version.h", "tbb/tbb_stddef.h", "tbb/version.h"):
        path = include / relative
        if not path.is_file():
            continue
        text = path.read_text(errors="replace")
        major = re.search(r"#define\s+TBB_VERSION_MAJOR\s+(\d+)", text)
        minor = re.search(r"#define\s+TBB_VERSION_MINOR\s+(\d+)", text)
        if major and minor:
            return {"tbb": f"{major.group(1)}.{minor.group(1)}"}
    return {}


def _opensubdiv_version(include: Path, _known: dict[str, str]) -> dict[str, str]:
    path = include / "opensubdiv" / "version.h"
    if not path.is_file():
        return {}
    text = path.read_text(errors="replace")
    major = re.search(r"#define\s+OPENSUBDIV_VERSION_MAJOR\s+(\d+)", text)
    minor = re.search(r"#define\s+OPENSUBDIV_VERSION_MINOR\s+(\d+)", text)
    if major and minor:
        return {"opensubdiv": f"{major.group(1)}.{minor.group(1)}"}
    return {}


def validate(result: Probe, require_python: bool = True) -> list[str]:
    """Return the reasons opendcc cannot be built against this USD, empty when it can."""
    problems: list[str] = []
    missing = [lib for lib in REQUIRED_USD_LIBS if lib not in result.libs]
    if missing:
        problems.append(
            "USD was built without libraries opendcc needs: "
            + ", ".join(missing)
            + " (rebuild USD with PXR_BUILD_IMAGING=ON, PXR_BUILD_USD_IMAGING=ON, "
            "PXR_ENABLE_GL_SUPPORT=ON)"
        )
    if require_python and not result.has_python_bindings:
        problems.append(
            "USD has no python bindings (lib/python/pxr missing); opendcc requires "
            "PXR_ENABLE_PYTHON_SUPPORT=ON"
        )
    if result.python is None:
        problems.append(
            "cannot determine the Python version the USD build used "
            "(no find_dependency(Python3 ...) and no python path in pxrConfig.cmake)"
        )
    return problems
