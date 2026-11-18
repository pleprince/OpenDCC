# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""VERSIONS.md is the single source of truth for dependency versions.

Three tables are read from it:

  ## OpenUSD releases          one row per OpenUSD release tag -> the VFX stack that release is
                               built and linked against (python, boost, tbb, oiio, ocio, ...)
  ## Build platform            versions that do not follow the OpenUSD release (qt, pyside,
                               clang, cmake, ninja, ...)
  ## Source-built dependencies third-party components pixi does not package, with version + URL

Nothing in this package knows a version number; a missing row or column is an error, never a
silent fallback.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

# Column / component header in VERSIONS.md -> canonical dependency name used everywhere else.
HEADERS = {
    "openusd": "usd",
    "python": "python",
    "qt": "qt",
    "pyside": "pyside",
    "boost": "boost",
    "tbb": "tbb",
    "opensubdiv": "opensubdiv",
    "openimageio": "openimageio",
    "opencolorio": "opencolorio",
    "openexr": "openexr",
    "imath": "imath",
    "materialx": "materialx",
    "osl": "openshadinglanguage",
    "openshadinglanguage": "openshadinglanguage",
    "embree": "embree",
    "embree 4": "embree4",
    "pybind11": "pybind11",
    "clang": "libclang",
    "libclang": "libclang",
    "cmake": "cmake",
    "ninja": "ninja",
    "glew": "glew",
    "zeromq": "zeromq",
    "eigen": "eigen",
    "graphviz": "graphviz",
    "doctest": "doctest",
    "fmt": "fmt",
    "bullet": "bullet",
    "qtads": "qtads",
    "qt advanced docking system": "qtads",
    "sentry-native": "sentry",
    "sentry": "sentry",
    "libigl": "libigl",
    "openmesh": "openmesh",
    "jinja2": "jinja2",
    "six": "six",
    "pygments": "pygments",
    "qt.py": "qt.py",
    "numpy": "numpy",
}


class VersionsError(RuntimeError):
    pass


@dataclass(frozen=True)
class Release:
    """One OpenUSD release row: the stack opendcc is built against for that release."""

    tag: str  # normalized, e.g. "25.11"
    pins: dict[str, str] = field(default_factory=dict)

    @property
    def git_tag(self) -> str:
        return "v" + self.tag


@dataclass(frozen=True)
class SourceComponent:
    name: str
    version: str
    url: str


@dataclass(frozen=True)
class Versions:
    releases: dict[str, Release]
    platform: dict[str, str]  # canonical name -> version
    sources: dict[str, SourceComponent]

    def release(self, tag: str) -> Release:
        wanted = normalize_tag(tag)
        if wanted in self.releases:
            return self.releases[wanted]
        known = ", ".join(sorted(self.releases, key=parse_tag)) or "<none>"
        raise VersionsError(
            f"OpenUSD release {wanted} is not in VERSIONS.md (known: {known}).\n"
            "Add a row to the 'OpenUSD releases' table first; the build never guesses a stack."
        )

    def release_pins(self, tag: str) -> dict[str, str]:
        """Everything pixi installs to build OpenUSD ``tag`` from source and link opendcc to it."""
        pins = dict(self.platform)
        pins.update(self.release(tag).pins)
        pins.pop("usd", None)
        return pins


def normalize_tag(tag: str) -> str:
    """'v25.11', '25.11.0' and '25.11' all name the same release."""
    t = tag.strip().removeprefix("v")
    m = re.match(r"^(\d+)\.(\d+)", t)
    if not m:
        raise VersionsError(f"{tag!r} is not an OpenUSD release tag")
    return f"{int(m.group(1))}.{int(m.group(2)):02d}"


def parse_tag(tag: str) -> tuple[int, int]:
    major, minor = tag.split(".")
    return (int(major), int(minor))


def parse(path: Path) -> Versions:
    sections = _sections(Path(path).read_text(encoding="utf-8"))
    return Versions(
        releases=_parse_releases(sections.get("OpenUSD releases")),
        platform=_parse_platform(sections.get("Build platform")),
        sources=_parse_sources(sections.get("Source-built dependencies")),
    )


# --------------------------------------------------------------------------------------------
# markdown table plumbing


def _sections(text: str) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    current: str | None = None
    for line in text.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            current = m.group(1).strip()
            out[current] = []
            continue
        if current is not None:
            out[current].append(line)
    return out


def _table(
    lines: list[str], where: str, columns: int | None = None
) -> tuple[list[str], list[list[str]]]:
    header: list[str] | None = None
    rows: list[list[str]] = []
    for line in lines:
        s = line.strip()
        if not s.startswith("|"):
            if header is not None and rows:
                break  # a table ends at the first non-table line after its rows
            continue
        cells = [re.sub(r"[`*]", "", c).strip() for c in s.strip("|").split("|")]
        if all(re.fullmatch(r":?-{2,}:?", c) for c in cells):
            continue
        if header is None:
            header = cells
        else:
            rows.append(cells)
    if header is None:
        raise VersionsError(f"VERSIONS.md has no table under '{where}'")
    if columns is not None and len(header) != columns:
        raise VersionsError(
            f"VERSIONS.md: table under '{where}' has {len(header)} columns, expected {columns}"
        )
    return header, rows


def _canonical(header: str, where: str) -> str:
    key = re.sub(r"[`*]", "", header).strip().lower()
    if key in HEADERS:
        return HEADERS[key]
    raise VersionsError(
        f"VERSIONS.md: '{header}' in '{where}' is not a known dependency. "
        f"Known: {', '.join(sorted(set(HEADERS)))}"
    )


def _parse_releases(lines: list[str] | None) -> dict[str, Release]:
    if not lines:
        raise VersionsError("VERSIONS.md has no '## OpenUSD releases' section")
    header, rows = _table(lines, "OpenUSD releases")
    names = [_canonical(h, "OpenUSD releases") for h in header]
    if names[0] != "usd":
        raise VersionsError("VERSIONS.md: first column of 'OpenUSD releases' must be OpenUSD")
    releases: dict[str, Release] = {}
    for cells in rows:
        if len(cells) != len(names):
            raise VersionsError(
                f"VERSIONS.md: row {cells[0]!r} has {len(cells)} cells, header has {len(names)}"
            )
        pins = {n: v for n, v in zip(names[1:], cells[1:]) if v not in ("", "-")}
        releases[normalize_tag(cells[0])] = Release(normalize_tag(cells[0]), pins)
    if not releases:
        raise VersionsError("VERSIONS.md: the 'OpenUSD releases' table is empty")
    return releases


def _parse_platform(lines: list[str] | None) -> dict[str, str]:
    if not lines:
        raise VersionsError("VERSIONS.md has no '## Build platform' section")
    _header, rows = _table(lines, "Build platform", columns=2)
    out: dict[str, str] = {}
    for cells in rows:
        out[_canonical(cells[0], "Build platform")] = cells[1]
    return out


def _parse_sources(lines: list[str] | None) -> dict[str, SourceComponent]:
    if not lines:
        raise VersionsError("VERSIONS.md has no '## Source-built dependencies' section")
    header, rows = _table(lines, "Source-built dependencies", columns=3)
    if [h.lower() for h in header] != ["component", "version", "source"]:
        raise VersionsError(
            "VERSIONS.md: 'Source-built dependencies' must be Component | Version | Source"
        )
    out: dict[str, SourceComponent] = {}
    for cells in rows:
        name = _canonical(cells[0], "Source-built dependencies")
        out[name] = SourceComponent(name=name, version=cells[1], url=cells[2])
    return out
