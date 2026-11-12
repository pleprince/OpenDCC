# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""Load, merge and validate the dependency spec.

The tracked file (``deps/<platform>.json``) is the only place dependency versions and feature switches are
declared. A gitignored overlay (``deps/<platform>.local.json``) overrides it per user. Merging happens here
and only here: CMake never parses JSON, it consumes the generated cache the driver writes.
"""

import json
import os
import platform
import re
import sys

PLATFORM = "macos-arm64"
SPEC_DIR = "deps"
OVERLAY_SUFFIX = ".local.json"

# Dependency order is the provisioning order; recipes may not rely on it (dependencies are resolved from
# `requires()`), but reports read better when the foundation comes first.
KNOWN_DEPS = [
    "python",
    "boost",
    "eigen",
    "tbb",
    "glew",
    "zmq",
    "graphviz",
    "doctest",
    "openmesh",
    "opensubdiv",
    "openimageio",
    "fmt",
    "opencolorio",
    "imath",
    "openexr",
    "sentry",
    "llvm",
    "qtbase",
    "qtmultimedia",
    "qtsvg",
    "qttools",
    "qtshadertools",
    "qtdeclarative",
    "qtquick3d",
    "pybind11",
    "embree",
    "bullet",
    "qtads",
    "libigl",
    "usd",
    "pyside",
    "alembic",
    "openvdb",
    "ptex",
    "hdf5",
    "partio",
    "draco",
    "materialx",
    "skia",
    "opentimelineio",
    "arnold",
    "cycles",
    "osl",
]

# USD build switches, in the order they are emitted into the generated cache.
USD_FEATURES = [
    "imaging",
    "usd_imaging",
    "usd_tools",
    "usdview",
    "python",
    "gl",
    "metal",
    "openimageio",
    "fmt",
    "opencolorio",
    "hdf5",
    "ptex",
    "alembic",
    "openvdb",
    "embree",
    "prman",
    "materialx",
    "draco",
    "osl",
    "tests",
    "examples",
    "tutorials",
]

# spec key -> generated CMake option (1:1, no other mapping).
OPENDCC_KEYS = {
    "tests": "DCC_BUILD_TESTS",
    "i18n": "DCC_BUILD_I18N",
    "crash_reporter": "DCC_BUILD_CRASH_REPORTER",
    "render_view": "DCC_BUILD_RENDER_VIEW",
    "node_editor": "DCC_NODE_EDITOR",
    "bullet_physics": "DCC_BUILD_BULLET_PHYSICS",
    "arnold_support": "DCC_BUILD_ARNOLD_SUPPORT",
    "cycles_support": "DCC_BUILD_CYCLES_SUPPORT",
    "renderman_support": "DCC_BUILD_RENDERMAN_SUPPORT",
    "use_ptex": "DCC_USE_PTEX",
    "use_houdini": "DCC_HOUDINI_SUPPORT",
    "use_katana": "DCC_KATANA_SUPPORT",
}

PROVIDERS = {"brew", "source", "headers", "manual"}

DEP_KEYS = {
    "enabled",
    "provider",
    "formula",
    "version",
    "expect",
    "url",
    "sha256",
    "strip",
    "features",
    "cmake_vars",
}

TOP_KEYS = {"schema", "platform", "python", "qt", "ocio", "opendcc", "dependencies"}

# Dependency-level edges. A disabled dependency listed here may not be required by an enabled one.
DEP_REQUIRES = {
    "qttools": ["qtbase"],
    "qtmultimedia": ["qtbase"],
    "qtsvg": ["qtbase"],
    "qtshadertools": ["qtbase"],
    "pyside": ["qtbase", "qtshadertools", "qtdeclarative", "qtquick3d", "python", "llvm"],
    "usd": ["python"],
    # Homebrew ships each Qt module as its own keg, so a module whose CMake config references another module's
    # private package (QtMultimedia -> Qml) only resolves when that keg is present.
    "qtmultimedia": ["qtbase", "qtdeclarative", "qtquick3d"],
    "qtdeclarative": ["qtbase"],
    "qtquick3d": ["qtbase", "qtdeclarative"],
    # OpenImageIO's bottled public headers include <fmt/format.h>.
    "openimageio": ["fmt"],
}

# usd.features.<feature> needs the matching dependency.
USD_FEATURE_DEPS = {
    "alembic": "alembic",
    "openvdb": "openvdb",
    "ptex": "ptex",
    "embree": "embree",
    "materialx": "materialx",
    "draco": "draco",
    "hdf5": "hdf5",
    "openimageio": "openimageio",
    "opencolorio": "opencolorio",
}

# usd.features.<feature> implies another usd feature.
USD_FEATURE_IMPLIES = {"usd_imaging": "imaging", "usdview": "imaging"}

# Features with no macOS arm64 build at all; enabling them is an error, not a missing dependency.
USD_UNSUPPORTED = {"prman": "has no macOS arm64 build"}

# opendcc.<key> needs the matching dependency.
OPENDCC_REQUIRES = {
    "tests": ["doctest"],
    "crash_reporter": ["sentry"],
    "render_view": ["qtmultimedia"],
    "node_editor": ["graphviz"],
    "bullet_physics": ["bullet"],
    "use_ptex": ["ptex"],
    "arnold_support": ["arnold"],
    "cycles_support": ["cycles", "osl"],
}


class SpecError(Exception):
    """Raised when the merged spec cannot be used; the message lists every problem."""

    def __init__(self, problems):
        self.problems = problems
        super().__init__("\n".join(problems))


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def detect_platform():
    """Return the spec platform tag for this host, or raise with the tag we would have looked for."""
    if sys.platform == "darwin" and platform.machine() == "arm64":
        return PLATFORM
    host = "{}-{}".format(sys.platform, platform.machine())
    raise SpecError(
        [
            "no dependency spec for {} (expected deps/{}.json); pass --spec to override".format(
                host, host
            )
        ]
    )


def default_spec_path(tag=None):
    return os.path.join(repo_root(), SPEC_DIR, "{}.json".format(tag or detect_platform()))


def default_overlay_path(spec_path):
    return os.path.splitext(spec_path)[0] + OVERLAY_SUFFIX


def rel(path):
    """Path relative to the repo root when it lives under it, else unchanged."""
    if not path:
        return path
    root = repo_root()
    try:
        common = os.path.commonpath([os.path.abspath(path), root])
    except ValueError:
        return path
    if common != root:
        return path
    return os.path.relpath(os.path.abspath(path), root)


def load(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except OSError as exc:
        raise SpecError(["cannot read {}: {}".format(rel(path), exc.strerror)])
    except ValueError as exc:
        raise SpecError(["{} is not valid JSON: {}".format(rel(path), exc)])


def deep_merge(base, overlay):
    """Merge ``overlay`` onto ``base``: objects merge recursively, scalars and arrays replace.

    A missing key keeps the base value, so an overlay only states what changes. The ``features`` map is an
    ordinary object, so per-feature overrides fall out of the same rule.
    """
    merged = dict(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def _split_version(value):
    return [int(part) for part in re.findall(r"\d+", str(value))]


def _cmp(a, b):
    length = max(len(a), len(b))
    a = a + [0] * (length - len(a))
    b = b + [0] * (length - len(b))
    return (a > b) - (a < b)


def version_matches(pin, installed):
    """True when ``installed`` satisfies a ``version`` pin.

    The pin's precision governs, so ``"4.3.5"`` accepts ``4.3.5_2`` and `"3.2.2"`` accepts ``3.2.2.0_1``;
    Homebrew revisions carry no meaning for us. ``"any"``/``None`` accept anything.
    """
    if pin in (None, "", "any"):
        return True
    if not installed:
        return False
    wanted = _split_version(pin)
    have = _split_version(str(installed).split("_")[0])
    return have[: len(wanted)] == wanted


def satisfies(expect, version):
    """Range check used by the recipes' own use; ``expect`` is separate from the ``version`` pin."""
    if expect in (None, "", "any") or version in (None, "", "any"):
        return True
    text = expect.strip()
    if text.startswith(">="):
        return _cmp(_split_version(version), _split_version(text[2:])) >= 0
    if text.startswith("=="):
        return version_matches(text[2:].strip(), version)
    raise SpecError(['unsupported "expect" range {!r}'.format(expect)])


def drift_message(name, installed, pin, overlay_file):
    return '{} is {}, spec expects {}; add {{"{}": {{"version": "{}"}}}} to {}'.format(
        name, installed or "not installed", pin, name, installed or pin, rel(overlay_file)
    )


def validate(merged, spec_file, overlay_file=None):
    """Validate the merged spec; returns a list of human-readable problems (empty when usable)."""
    problems = []
    base_name = rel(spec_file)
    overlay_name = rel(overlay_file) if overlay_file else None

    for key in merged:
        if key not in TOP_KEYS:
            problems.append('unknown key "{}" in {}'.format(key, base_name))

    if merged.get("schema") != 1:
        problems.append(
            '{}: "schema" must be 1, found {!r}'.format(base_name, merged.get("schema"))
        )
    if merged.get("platform") != PLATFORM:
        problems.append(
            '{}: "platform" must be "{}", found {!r}'.format(
                base_name, PLATFORM, merged.get("platform")
            )
        )

    python_block = merged.get("python") or {}
    if not isinstance(python_block, dict) or python_block.get("version") in (None, ""):
        problems.append('{}: "python".version is required'.format(base_name))

    qt = merged.get("qt") or {}
    if qt.get("version") in (None, ""):
        problems.append('{}: "qt".version is required'.format(base_name))
    if qt.get("pyside") in (None, ""):
        problems.append('{}: "qt".pyside is required'.format(base_name))
    if qt.get("version") and qt.get("pyside") and qt.get("version") != qt.get("pyside"):
        problems.append(
            "qt.version ({}) and qt.pyside ({}) must be the same release in {}".format(
                qt.get("version"), qt.get("pyside"), base_name
            )
        )

    ocio = merged.get("ocio") or {}
    if not isinstance(ocio, dict):
        problems.append('{}: "ocio" must be an object'.format(base_name))
        ocio = {}
    for key in ocio:
        if key not in {"config_version", "url", "sha256"}:
            problems.append('unknown ocio key "{}" in {}'.format(key, base_name))
    if ocio and not ocio.get("url"):
        problems.append('ocio.config must have a "url" in {}'.format(base_name))

    opendcc = merged.get("opendcc") or {}
    for key in opendcc:
        if key not in OPENDCC_KEYS:
            problems.append(
                'unknown opendcc key "{}" in {}; known: [{}]'.format(
                    key, base_name, ", ".join(sorted(OPENDCC_KEYS))
                )
            )
    for key, value in opendcc.items():
        if key in OPENDCC_KEYS and not isinstance(value, bool):
            problems.append("opendcc.{} must be true or false in {}".format(key, base_name))

    deps = merged.get("dependencies") or {}
    if not isinstance(deps, dict):
        problems.append('{}: "dependencies" must be an object'.format(base_name))
        deps = {}

    # Point unknown names at the overlay when the overlay is what introduced them, and report each name once.
    overlay_deps = (load(overlay_file).get("dependencies") or {}) if overlay_file else {}
    if isinstance(overlay_deps, dict):
        for dep_name in overlay_deps:
            if dep_name not in KNOWN_DEPS:
                problems.append(
                    'unknown dependency "{}" in {}; known: [{}]'.format(
                        dep_name, overlay_name, ", ".join(KNOWN_DEPS)
                    )
                )
    unknown = {name for name in deps if name not in KNOWN_DEPS}
    unknown -= set(overlay_deps) if isinstance(overlay_deps, dict) else set()
    for dep_name in unknown:
        problems.append(
            'unknown dependency "{}" in {}; known: [{}]'.format(
                dep_name, base_name, ", ".join(KNOWN_DEPS)
            )
        )

    for name, dep in deps.items():
        if name not in KNOWN_DEPS:
            continue
        where = base_name if not overlay_file else overlay_name
        if not isinstance(dep, dict):
            problems.append('dependency "{}" must be an object ({})'.format(name, base_name))
            continue
        for key in dep:
            if key not in DEP_KEYS:
                problems.append(
                    'unknown key "{}" for dependency "{}" in {}; known: [{}]'.format(
                        key, name, where, ", ".join(sorted(DEP_KEYS))
                    )
                )
        if not isinstance(dep.get("enabled"), bool):
            problems.append('{}: "enabled" must be true or false in {}'.format(name, base_name))
        provider = dep.get("provider")
        if provider not in PROVIDERS:
            problems.append(
                '{}: "provider" must be one of {} in {}'.format(
                    name, ", ".join(sorted(PROVIDERS)), base_name
                )
            )
            continue
        if provider == "brew" and not dep.get("formula"):
            problems.append('{}: brew provider needs a "formula" in {}'.format(name, base_name))
        if provider in ("source", "headers") and dep.get("enabled") and not dep.get("url"):
            problems.append(
                'enabled {} dependency "{}" has no "url" in {}'.format(provider, name, where)
            )
        if dep.get("expect") is not None and dep.get("version") not in (None, "", "any"):
            try:
                satisfies(dep.get("expect"), dep.get("version"))
            except SpecError as exc:
                problems.append("{}: {}".format(name, exc.problems[0]))
        features = dep.get("features")
        if features is not None:
            if name != "usd":
                problems.append(
                    'only "usd" takes a "features" map, found in {} ({})'.format(name, base_name)
                )
            else:
                for feature in features:
                    if feature not in USD_FEATURES:
                        problems.append(
                            'unknown usd feature "{}" in {}; known: [{}]'.format(
                                feature, where, ", ".join(USD_FEATURES)
                            )
                        )
                for feature, value in features.items():
                    if feature in USD_FEATURES and not isinstance(value, bool):
                        problems.append(
                            "usd.features.{} must be true or false in {}".format(feature, base_name)
                        )

    usd = deps.get("usd") or {}
    usd_features = usd.get("features") or {}
    usd_enabled = bool(usd.get("enabled"))
    pyside = deps.get("pyside") or {}

    if qt.get("pyside") and pyside.get("version") and pyside["version"] != qt["pyside"]:
        problems.append(
            "dependencies.pyside.version ({}) must equal qt.pyside ({}) in {}".format(
                pyside["version"], qt["pyside"], base_name
            )
        )

    if usd_enabled:
        for feature, dep_name in USD_FEATURE_DEPS.items():
            if usd_features.get(feature) and not (deps.get(dep_name) or {}).get("enabled"):
                problems.append(
                    'usd.features.{} requires dependency "{}" (disabled in {})'.format(
                        feature, dep_name, base_name
                    )
                )
        for feature, reason in USD_UNSUPPORTED.items():
            if usd_features.get(feature):
                problems.append("usd.features.{} {}".format(feature, reason))
        for feature, implied in USD_FEATURE_IMPLIES.items():
            if usd_features.get(feature) and not usd_features.get(implied):
                problems.append(
                    "usd.features.{} requires usd.features.{} in {}".format(
                        feature, implied, base_name
                    )
                )

    for owner, required in DEP_REQUIRES.items():
        if not (deps.get(owner) or {}).get("enabled"):
            continue
        for dep_name in required:
            if not (deps.get(dep_name) or {}).get("enabled"):
                problems.append(
                    'dependency "{}" is required by "{}"; enable it or disable "{}"'.format(
                        dep_name, owner, owner
                    )
                )

    for key, required in OPENDCC_REQUIRES.items():
        if not opendcc.get(key):
            continue
        for dep_name in required:
            if not (deps.get(dep_name) or {}).get("enabled"):
                problems.append(
                    'opendcc.{} requires dependency "{}" (disabled in {})'.format(
                        key, dep_name, base_name
                    )
                )

    if bool(opendcc.get("use_ptex")) != bool(usd_features.get("ptex")):
        problems.append(
            "opendcc.use_ptex ({}) and usd.features.ptex ({}) must be equal; set both in {}".format(
                str(bool(opendcc.get("use_ptex"))).lower(),
                str(bool(usd_features.get("ptex"))).lower(),
                base_name,
            )
        )

    return problems


def resolve(spec_file, overlay_file=None, require_overlay=False):
    """Load + merge + validate. Returns ``(merged, base_dict, overlay_dict)``."""
    base = load(spec_file)
    overlay = {}
    if require_overlay and not overlay_file:
        raise SpecError(["no overlay file given"])
    if overlay_file and os.path.exists(overlay_file):
        overlay = load(overlay_file)
    merged = deep_merge(base, overlay if overlay else {})
    problems = validate(merged, spec_file, overlay_file if overlay else None)
    if problems:
        raise SpecError(problems)
    return merged, base, overlay
