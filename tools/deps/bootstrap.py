#!/usr/bin/env python3
# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""Provision the dependency prefix declared by deps/<platform>.json.

The spec is the only source of truth for which dependencies and which dependency features are enabled, at
which versions. This driver merges it with the user overlay, validates the result, provisions everything that
is enabled (Homebrew bottle where the version matches, source build otherwise) and writes the single file
CMake consumes: ``<prefix>/deps.generated.cmake``.

Stdlib only; downloads shell out to curl.
"""

import argparse
import glob
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import recipes
import spec as specmod

BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
INF = "\033[0m"


class ProvisionError(Exception):
    pass


def say(message=""):
    print(message, flush=True)


def info(message):
    say("  " + message)


def die(message):
    raise ProvisionError(message)


# ----------------------------------------------------------------------------------------------------------
# process helpers


def run(argv, check=True, cwd=None, env=None, capture=True):
    kwargs = {}
    if capture:
        kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        proc = subprocess.run(argv, cwd=cwd, env=env, check=False, **kwargs)
    except FileNotFoundError:
        die("{} not found; install it or fix PATH".format(argv[0]))
    if check and proc.returncode != 0:
        die(
            "command failed ({}): {}\n{}".format(
                proc.returncode, " ".join(argv), (proc.stdout or "").strip()
            )
        )
    return proc


def tail(path, count=40):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            lines = handle.readlines()
    except OSError:
        return ""
    return "".join(lines[-count:])


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_json(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()


# ----------------------------------------------------------------------------------------------------------
# context


class Ctx:
    """Resolved paths and shared state the recipes build against."""

    DIRS = ("downloads", "src", "build", "stamps", "venv", "lib", "bin", "include", "share")

    def __init__(self, repo, prefix, merged, spec_file, overlay_file, jobs, arch="arm64"):
        self.repo = repo
        self.prefix = prefix
        self.merged = merged
        self.spec_file = spec_file
        self.overlay_file = overlay_file
        self.jobs = jobs
        self.arch = arch
        self.cmake = shutil.which("cmake") or "cmake"
        self.lock = load_lock(spec_file)
        self.lock_dirty = False
        self._kegs = {}

    def ensure_layout(self):
        for name in self.DIRS:
            os.makedirs(os.path.join(self.prefix, name), exist_ok=True)

    def dep(self, name):
        return self.merged["dependencies"][name]

    def version_of(self, name):
        """The spec pin for a dependency, for recipes whose build needs its own version as an argument."""
        return self.merged["dependencies"][name].get("version")

    def brew_prefix(self, formula):
        proc = run(["brew", "--prefix", formula], check=False)
        path = (proc.stdout or "").strip()
        if proc.returncode != 0 or not path or not os.path.exists(path):
            return None
        return path

    def keg(self, name):
        """Directory to build against: that dependency's Homebrew keg, or our own prefix for source builds."""
        if name in self._kegs:
            return self._kegs[name]
        dep = self.merged["dependencies"].get(name)
        if dep is None:
            die('unknown dependency "{}" requested by a recipe'.format(name))
        provider = dep.get("provider")
        if provider == "brew":
            path = self.brew_prefix(dep["formula"])
            if not path:
                die(
                    'brew formula "{}" for dependency "{}" is not installed; run this driver first'.format(
                        dep["formula"], name
                    )
                )
            self._kegs[name] = path
            return path
        if provider in ("source", "headers"):
            return self.prefix
        die(
            'dependency "{}" uses provider "{}" and its location cannot be derived'.format(
                name, provider
            )
        )

    @property
    def sdkroot(self):
        """The SDK sysroot; libclang (Homebrew's, not Apple's) only finds SDK headers when told."""
        if not hasattr(self, "_sdkroot"):
            proc = run(["xcrun", "--show-sdk-path"], check=False)
            self._sdkroot = (proc.stdout or "").strip() if proc.returncode == 0 else ""
        return self._sdkroot

    @property
    def python_exe(self):
        return os.path.join(self.prefix, "venv", "bin", "python3")

    def prepend_paths(self, paths):
        return os.pathsep.join([p for p in paths if p] + [os.environ.get("PATH", "")])


# ----------------------------------------------------------------------------------------------------------
# spec/lock plumbing


def spec_token(spec_file, overlay_file):
    """Mirror of the CMake guard: sha256 over "path|mtime|size;" for every spec file that exists."""
    parts = []
    for path in (spec_file, overlay_file):
        if path and os.path.exists(path):
            stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime(os.path.getmtime(path)))
            parts.append("{}|{}|{};".format(os.path.abspath(path), stamp, os.path.getsize(path)))
    return hashlib.sha256("".join(parts).encode("utf-8")).hexdigest()


def lock_path(spec_file):
    return os.path.splitext(spec_file)[0] + ".lock.json"


def load_lock(spec_file):
    path = lock_path(spec_file)
    if not os.path.exists(path):
        return {"schema": 1, "sources": {}}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except ValueError as exc:
        die("{} is not valid JSON: {}".format(specmod.rel(path), exc))
    data.setdefault("schema", 1)
    data.setdefault("sources", {})
    return data


def save_lock(ctx):
    path = lock_path(ctx.spec_file)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(ctx.lock, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return path


# ----------------------------------------------------------------------------------------------------------
# Homebrew


def brew_version(ctx, formula):
    path = ctx.brew_prefix(formula)
    return os.path.basename(os.path.realpath(path)) if path else None


def ensure_brew(ctx, name, dep):
    """Install or upgrade ``dep``'s formula until the keg satisfies the spec pin."""
    formula = dep["formula"]
    pin = dep.get("version")
    installed = brew_version(ctx, formula)
    if installed and specmod.version_matches(pin, installed):
        return installed
    if not shutil.which("brew"):
        die("brew is required to provision {}; install Homebrew first".format(name))
    if installed:
        say("  {}: upgrading brew {} ({} -> {})".format(name, formula, installed, pin))
        proc = run(["brew", "upgrade", "--formula", formula], check=False)
        action = "upgrade"
    else:
        say("  {}: installing brew {}".format(name, formula))
        proc = run(["brew", "install", "--formula", formula], check=False)
        action = "install"
    after = brew_version(ctx, formula)
    if not specmod.version_matches(pin, after):
        if proc.returncode != 0:
            output = (proc.stdout or "").strip().splitlines()
            die("brew {} of {} failed:\n{}".format(action, formula, "\n".join(output[-20:])))
        die(specmod.drift_message(name, after, pin, ctx.overlay_file) + "; then re-run this driver")
    if not specmod.satisfies(dep.get("expect"), after):
        say(
            "  {}: warning: brew {} is {}, outside the expected range {}".format(
                name, formula, after, dep.get("expect")
            )
        )
    return after


# ----------------------------------------------------------------------------------------------------------
# archives


ARCHIVE_SUFFIXES = (".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".zip", ".tar")


def archive_name(dep):
    """A file name that keeps the archive type: codeload URLs end in a tag, not in an extension."""
    url = dep["url"]
    base = os.path.basename(urllib.parse.urlparse(url).path) or "archive"
    if base.endswith(ARCHIVE_SUFFIXES):
        return base
    for marker, suffix in (("/tar.gz/", ".tar.gz"), ("/tar.xz/", ".tar.xz"), ("/zip/", ".zip")):
        if marker in url:
            return base + suffix
    return base + ".tar.gz"


def archive_path(ctx, dep):
    return os.path.join(ctx.prefix, "downloads", archive_name(dep))


def download(ctx, name, dep, rehash=False):
    """Fetch ``dep`` into <prefix>/downloads and pin its sha256 in the lock. Returns (path, sha256)."""
    url = dep["url"]
    target = archive_path(ctx, dep)
    locked = ctx.lock["sources"].get(name) or {}
    if locked.get("url") not in (None, url):
        # The spec now points at a different artifact (a version bump), so the recorded hash belongs to the previous
        # one and cannot be checked against it. Same-URL bytes that changed are still caught below.
        locked = {}
    pinned = dep.get("sha256") or locked.get("sha256")
    if os.path.exists(target) and not rehash and pinned and sha256_file(target) == pinned:
        return target, pinned
    if not os.path.exists(target):
        say("  {}: downloading {}".format(name, url))
        partial = target + ".part"
        run(
            [
                "curl",
                "--fail",
                "--location",
                "--retry",
                "3",
                "--silent",
                "--show-error",
                "--output",
                partial,
                url,
            ],
            capture=False,
        )
        digest = sha256_file(partial)
        if pinned and digest != pinned:
            os.unlink(partial)
            die(
                "sha256 mismatch for {}: pinned {}, download is {} ({}). If the upstream tag was re-cut, "
                'set "sha256": null in the spec and re-run with --update-lock'.format(
                    name, pinned, digest, "spec" if dep.get("sha256") else "lock"
                )
            )
        os.replace(partial, target)
    digest = sha256_file(target)
    if pinned and digest != pinned:
        die(
            "sha256 mismatch for {}: pinned {}, {} is {}".format(
                name, pinned, specmod.rel(target), digest
            )
        )
    recorded = (ctx.lock["sources"].get(name) or {}).get("sha256")
    if recorded != digest or (ctx.lock["sources"].get(name) or {}).get("url") != url:
        say("  {}: recorded sha256 {} for {}".format(name, digest, name))
        ctx.lock["sources"][name] = {"url": url, "sha256": digest}
        ctx.lock_dirty = True
    return target, digest


def _extract_all(archive, destination):
    with tarfile.open(archive) as handle:
        try:
            handle.extractall(destination, filter="data")
        except TypeError:  # tarfile's filter= needs Python 3.12+
            handle.extractall(destination)


def extract_stripped(archive, destination, strip):
    work = destination + ".extract"
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work, exist_ok=True)
    _extract_all(archive, work)
    source = work
    if strip:
        entries = sorted(os.listdir(work))
        if len(entries) != 1 or not os.path.isdir(os.path.join(work, entries[0])):
            die("{}: expected exactly one top-level directory".format(archive))
        source = os.path.join(work, entries[0])
    shutil.rmtree(destination, ignore_errors=True)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    shutil.move(source, destination)
    shutil.rmtree(work, ignore_errors=True)
    return destination


# ----------------------------------------------------------------------------------------------------------
# stamps


def stamp_file(ctx, name):
    return os.path.join(ctx.prefix, "stamps", name + ".json")


def read_stamp(ctx, name):
    try:
        with open(stamp_file(ctx, name), "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def write_stamp(ctx, name, dep, digest):
    payload = {
        "version": dep.get("version"),
        "options_sha256": digest,
        "installed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    path = stamp_file(ctx, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


PATCH_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "patches")


def patch_digests(recipe):
    digests = []
    for name in recipe.patches:
        path = os.path.join(PATCH_DIR, name)
        if not os.path.exists(path):
            die("patch {} is missing from {}".format(name, PATCH_DIR))
        digests.append([name, sha256_file(path)])
    return digests


def _normalise_argv(argv):
    """Drop the parallel job count: it changes the build speed, never the build output."""
    normalised = []
    skip_next = False
    for argument in argv:
        if skip_next:
            skip_next = False
            continue
        if argument in ("-j", "--parallel"):
            normalised.append(argument)
            skip_next = True
            continue
        if argument.startswith("--parallel="):
            normalised.append("--parallel")
            continue
        normalised.append(argument)
    return normalised


def recipe_digest(ctx, name, dep, recipe):
    """Hash of everything that decides what gets built: version, features, patches and the resulting arguments."""
    features = dep.get("features") or {}
    src = os.path.join(ctx.prefix, "src", name)
    steps = recipe.steps(src, os.path.join(ctx.prefix, "build", name), features, ctx)
    return sha256_json(
        {
            "kind": recipe.kind,
            "version": dep.get("version"),
            "url": dep.get("url"),
            "features": features,
            "patches": patch_digests(recipe),
            "steps": [[label, _normalise_argv(argv)] for label, argv in steps],
        }
    )


def apply_patches(ctx, name, recipe, src):
    for patch_name in recipe.patches:
        path = os.path.join(PATCH_DIR, patch_name)
        say("  {}: applying {}".format(name, patch_name))
        proc = run(
            ["patch", "-p1", "--forward", "--batch", "--silent", "-d", src, "-i", path],
            check=False,
        )
        if proc.returncode != 0:
            die(
                "{}: {} did not apply cleanly; the archive or the patch changed:\n{}".format(
                    name, patch_name, (proc.stdout or "").strip()
                )
            )


# ----------------------------------------------------------------------------------------------------------
# provisioning


def ensure_venv(ctx, force=False):
    """The interpreter the recipes and the app build share; Homebrew's python@3.12 is keg-only."""
    python_dep = ctx.merged["dependencies"]["python"]
    keg = ctx.brew_prefix(python_dep["formula"])
    if not keg:
        die(
            'brew formula "{}" is not installed; provision "python" first'.format(
                python_dep["formula"]
            )
        )
    version = ctx.merged["python"]["version"]
    exe = os.path.join(keg, "bin", "python" + version)
    if not os.path.exists(exe):
        die("{} is missing; is {} installed completely?".format(exe, python_dep["formula"]))
    packages = [
        "--upgrade",
        "pip",
        "setuptools",
        "wheel",
        "packaging",
        "pygments==2.5.2",
        "qt.py==2.0.5",
        # Imported by the application's own python packages.
        "six",
        "numpy",
        # usdGenSchema (run at build time to generate USD schema code) imports jinja2.
        "jinja2",
    ]
    digest = sha256_json([version, packages])
    stamp = read_stamp(ctx, "venv")
    if (
        stamp
        and stamp.get("options_sha256") == digest
        and os.path.exists(ctx.python_exe)
        and not force
    ):
        say("  venv up to date ({})".format(ctx.python_exe))
        return
    if force or not os.path.exists(ctx.python_exe):
        venv_dir = os.path.join(ctx.prefix, "venv")
        say("  venv: creating {} with {}".format(venv_dir, exe))
        shutil.rmtree(venv_dir, ignore_errors=True)
        run([exe, "-m", "venv", venv_dir], capture=False)
    say("  venv: installing " + " ".join(p for p in packages if not p.startswith("-")))
    run([ctx.python_exe, "-m", "pip", "install", "--no-input"] + packages, capture=False)
    write_stamp(ctx, "venv", {"version": version}, digest)


OCIO_ASSET_NAME = "ocio-config"


def provision_ocio_config(ctx):
    """Fetch the OCIO config the application loads from <prefix>/ocio/config.ocio.

    It is runtime data rather than a library, so it is not part of the dependency graph, but it is versioned and
    checksummed like everything else.
    """
    ocio = ctx.merged.get("ocio") or {}
    if not ocio.get("url"):
        return
    dep = {
        "url": ocio["url"],
        "sha256": ocio.get("sha256"),
        "version": ocio.get("config_version") or "any",
    }
    archive, _ = download(ctx, OCIO_ASSET_NAME, dep)
    target_dir = os.path.join(ctx.prefix, "ocio")
    os.makedirs(target_dir, exist_ok=True)
    target = os.path.join(target_dir, "config.ocio")
    shutil.copyfile(archive, target)
    say("  ocio config: {} ({})".format(target, dep["version"]))


def provision_source(ctx, name, dep, force):
    recipe = recipes.RECIPES.get(name)
    if recipe is None:
        die(
            'enabled {} dependency "{}" has no recipe in tools/deps/recipes.py'.format(
                dep.get("provider"), name
            )
        )
    features = dep.get("features") or {}
    src = os.path.join(ctx.prefix, "src", name)
    build = os.path.join(ctx.prefix, "build", name)
    digest = recipe_digest(ctx, name, dep, recipe)
    stamp = read_stamp(ctx, name)
    if not force and stamp and stamp.get("options_sha256") == digest and recipe.present(ctx):
        say("  {}: up to date ({})".format(name, dep.get("version")))
        return "up to date"

    for required in recipe.requires(features):
        required_recipe = recipes.RECIPES.get(required)
        if required_recipe is not None and not required_recipe.present(ctx):
            die('{} requires "{}", which is not provisioned yet'.format(name, required))

    # A rebuild must not reuse objects produced from the previous source tree: the archive is re-extracted and the
    # patches reapplied, and a stale build directory silently keeps the old flags and files.
    if os.path.isdir(build):
        info("removing the previous build directory")
        shutil.rmtree(build, ignore_errors=True)

    archive, _ = download(ctx, name, dep)
    say("  {}: extracting {}".format(name, os.path.basename(archive)))
    extract_stripped(archive, src, dep.get("strip", 1))
    apply_patches(ctx, name, recipe, src)
    recipe.verify(src, features, ctx)

    steps = recipe.steps(src, build, features, ctx)
    if not steps:
        info("no build step ({})".format(recipe.kind))
    env = os.environ.copy()
    env.update(recipe.env(features, ctx))
    log_path = os.path.join(ctx.prefix, "build", name + ".log")
    os.makedirs(build, exist_ok=True)
    open(log_path, "w", encoding="utf-8").close()

    for label, argv in steps:
        say("  {}: {}: {}".format(name, label, " ".join(argv)))
        started = time.time()
        with open(log_path, "a", encoding="utf-8") as log:
            log.write("$ {}\n".format(" ".join(argv)))
            proc = subprocess.run(
                argv, env=env, cwd=build, stdout=log, stderr=subprocess.STDOUT, check=False
            )
        if proc.returncode != 0:
            say("")
            say(
                RED
                + "{} failed during {} after {}s".format(name, label, int(time.time() - started))
                + INF
            )
            say(DIM + "--- last 40 lines of the build log ---" + INF)
            say(tail(log_path, 40))
            die("{} failed; full log: {}".format(name, log_path))
        info("{}: {} ok ({}s)".format(name, label, int(time.time() - started)))

    if not recipe.present(ctx):
        die("{} built, but its expected files are missing from {}".format(name, ctx.prefix))
    write_stamp(ctx, name, dep, digest)
    return "built {}".format(dep.get("version"))


def provision_manual(ctx, name, dep):
    say("  {}: manual dependency, not provisioned by this driver".format(name))
    for variable, value in sorted((dep.get("cmake_vars") or {}).items()):
        if "@MANUAL@" in value:
            info("set {} so find_package({}) can locate it".format(variable, name))
    return "manual"


def provision(ctx, names, forced):
    for name in names:
        dep = ctx.dep(name)
        if not dep.get("enabled"):
            continue
        provider = dep.get("provider")
        say(BOLD + name + INF + ":")
        if provider == "brew":
            ensure_brew(ctx, name, dep)
        elif provider in ("source", "headers"):
            provision_source(ctx, name, dep, name in forced)
        elif provider == "manual":
            provision_manual(ctx, name, dep)
        else:
            die('{}: unsupported provider "{}"'.format(name, provider))
        say("")


# ----------------------------------------------------------------------------------------------------------
# generated cache


CMAKE_BOOL_DEFAULTS = {
    "DCC_USE_PYTHON_3": True,
    "DCC_PYSIDE_CMAKE_FIND": True,
    "DCC_INSTALL_USD": True,
    "DCC_INSTALL_PYSIDE2": True,
    "DCC_INSTALL_PYTHON": True,
}

FILEPATH_VARS = {"PYTHON_EXECUTABLE", "Python3_EXECUTABLE", "Python_EXECUTABLE"}

# Kept off CMAKE_PREFIX_PATH: llvm would let CMake pick Homebrew's clang, python is addressed through the venv.
PREFIX_PATH_EXCLUDE = {"python", "llvm"}


def cmake_quote(value):
    return '"{}"'.format(str(value).replace("\\", "\\\\").replace('"', '\\"'))


def expand_var(ctx, name, value):
    """Expand @FORMULA@/@PREFIX@; None when the value needs a path only the user knows."""
    if "@MANUAL@" in value:
        return None
    expanded = value.replace("@PREFIX@", ctx.prefix)
    return expanded.replace("@FORMULA@", ctx.keg(name))


def pyside_cmake_prefixes(ctx):
    """PySide ships its CMake packages inside the site-packages tree, not on any default search path.

    Layout: <site-packages>/<package>/lib/cmake/<Package>/<Package>Config.cmake, so the prefix CMake needs is
    <site-packages>/<package>.
    """
    pattern = os.path.join(
        ctx.prefix,
        "venv",
        "lib",
        "python*",
        "site-packages",
        "*",
        "lib",
        "cmake",
        "*",
        "*Config.cmake",
    )
    prefixes = set()
    for config in glob.glob(pattern):
        # <package>/lib/cmake/<Package>/<Package>Config.cmake -> <package>
        prefixes.add(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(config)))))
    return sorted(prefixes)


def _python_version(ctx):
    """major/minor of the pinned interpreter, for the site-packages layout."""
    parts = str(ctx.merged["python"]["version"]).split(".")
    return parts[0], parts[1] if len(parts) > 1 else "0"


def generated_cache_text(ctx):
    merged = ctx.merged
    deps = merged["dependencies"]
    enabled = [name for name in specmod.KNOWN_DEPS if (deps.get(name) or {}).get("enabled")]
    lines = [
        "# Generated by tools/deps/bootstrap.py from {}".format(specmod.rel(ctx.spec_file)),
        "# and {}. Do not edit: change the spec or the local overlay and re-run".format(
            specmod.rel(ctx.overlay_file) if os.path.exists(ctx.overlay_file) else "(no overlay)"
        ),
        "# the driver instead.",
        "",
        "set(DCC_DEPS_SPEC_FILE {})".format(cmake_quote(os.path.abspath(ctx.spec_file))),
        "set(DCC_DEPS_OVERLAY_FILE {})".format(
            cmake_quote(
                os.path.abspath(ctx.overlay_file) if os.path.exists(ctx.overlay_file) else ""
            )
        ),
        "set(DCC_DEPS_SPEC_TOKEN {})".format(
            cmake_quote(spec_token(ctx.spec_file, ctx.overlay_file))
        ),
        "set(DCC_DEPS_PREFIX {})".format(cmake_quote(ctx.prefix)),
        "",
    ]

    prefix_path = [ctx.prefix]
    prefix_path.extend(pyside_cmake_prefixes(ctx))
    for name in enabled:
        dep = deps[name]
        if dep.get("provider") == "brew" and name not in PREFIX_PATH_EXCLUDE:
            keg = ctx.brew_prefix(dep["formula"])
            if keg:
                prefix_path.append(keg)
    lines.append(
        "list(PREPEND CMAKE_PREFIX_PATH {})".format(" ".join(cmake_quote(p) for p in prefix_path))
    )
    lines.append("")

    lines.append(
        "# Which dependencies are enabled, and at which version. Authoritative, not cache variables."
    )
    for name in specmod.KNOWN_DEPS:
        dep = deps.get(name) or {}
        key = name.upper().replace("-", "_")
        lines.append(
            "set(DCC_DEPS_{}_ENABLED {})".format(key, "ON" if dep.get("enabled") else "OFF")
        )
        lines.append(
            "set(DCC_DEPS_{}_VERSION {})".format(key, cmake_quote(dep.get("version") or ""))
        )
    lines.append("")

    features = (deps.get("usd") or {}).get("features") or {}
    lines.append("# USD build switches, one per spec feature.")
    for feature in specmod.USD_FEATURES:
        lines.append(
            "set(DCC_DEPS_USD_FEATURE_{} {})".format(
                feature.upper(), "ON" if features.get(feature) else "OFF"
            )
        )
    lines.append("")

    # Widgets and packages import Qt.py and pygments at runtime, so they have to travel with the install tree.
    site_packages = os.path.join(
        ctx.prefix, "venv", "lib", "python{}.{}".format(*_python_version(ctx)), "site-packages"
    )
    lines.append("set(DCC_DEPS_PYTHON_SITE_PACKAGES {})".format(cmake_quote(site_packages)))
    lines.append("")

    ocio_config = os.path.join(ctx.prefix, "ocio", "config.ocio")
    if os.path.exists(ocio_config):
        lines.append("set(DCC_DEPS_OCIO_CONFIG_FILE {})".format(cmake_quote(ocio_config)))
        lines.append("")

    lines.append("# Finder roots, for enabled dependencies only.")
    emitted = set()
    # Qt resolves a component relative to the prefix its own Qt6Config.cmake lives under, and Homebrew ships each
    # module in a separate keg; pin the merged prefix so Qt6Svg/Qt6Multimedia/... are found from the app too.
    if (deps.get("qtbase") or {}).get("enabled"):
        merged_qt = recipes.qt_install_prefix(ctx)
        if os.path.exists(os.path.join(merged_qt, "lib", "cmake", "Qt6", "Qt6Config.cmake")):
            lines.append(
                'set(Qt6_DIR {} CACHE PATH "")'.format(
                    cmake_quote(os.path.join(merged_qt, "lib", "cmake", "Qt6"))
                )
            )
            emitted.add("Qt6_DIR")
    for name in enabled:
        for variable, value in sorted((deps[name].get("cmake_vars") or {}).items()):
            if variable in emitted:
                continue
            resolved = expand_var(ctx, name, value)
            if resolved is None:
                continue
            emitted.add(variable)
            cache_type = "FILEPATH" if variable in FILEPATH_VARS else "PATH"
            lines.append(
                'set({} {} CACHE {} "")'.format(variable, cmake_quote(resolved), cache_type)
            )
    lines.append("")

    lines.append("# Fixed by the provisioned-prefix model; a preset or -D value still wins.")
    for variable, value in CMAKE_BOOL_DEFAULTS.items():
        lines.append('set({} {} CACHE BOOL "")'.format(variable, "ON" if value else "OFF"))
    lines.append("")

    # opendcc.* from the spec. These are cache entries with FORCE on purpose: a plain default would be shadowed by
    # the value the previous configure left in CMakeCache.txt, so editing the spec would silently have no effect.
    # Change these in the spec, not with -D.
    lines.append(
        "# opendcc.* from the spec. Authoritative: change the spec, not a -D or preset value."
    )
    opendcc = merged.get("opendcc") or {}
    for variable, enabled in list(
        (variable, opendcc.get(key)) for key, variable in specmod.OPENDCC_KEYS.items()
    ) + [
        ("DCC_USD_FALLBACK_PROXY_BUILD_ARNOLD_USD", opendcc.get("arnold_support")),
        ("DCC_USD_FALLBACK_PROXY_BUILD_CYCLES", opendcc.get("cycles_support")),
    ]:
        lines.append('set({} {} CACHE BOOL "" FORCE)'.format(variable, "ON" if enabled else "OFF"))
    lines.append("")
    return "\n".join(lines)


def write_generated_cache(ctx):
    path = os.path.join(ctx.prefix, "deps.generated.cmake")
    os.makedirs(ctx.prefix, exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(generated_cache_text(ctx))
    os.replace(temporary, path)
    return path


# ----------------------------------------------------------------------------------------------------------
# reporting


def dep_state(ctx, name):
    dep = ctx.dep(name)
    if not dep.get("enabled"):
        return "disabled"
    provider = dep.get("provider")
    if provider == "brew":
        installed = brew_version(ctx, dep["formula"])
        if not installed:
            return "missing"
        if not specmod.version_matches(dep.get("version"), installed):
            return "drift"
        return "ok"
    if provider in ("source", "headers"):
        recipe = recipes.RECIPES.get(name)
        if recipe is None:
            return "no recipe"
        if not recipe.present(ctx):
            return "missing"
        stamp = read_stamp(ctx, name)
        if not stamp or stamp.get("options_sha256") != recipe_digest(ctx, name, dep, recipe):
            return "stale"
        return "ok"
    return "manual"


def state_colour(state):
    if state == "ok":
        return GREEN
    if state in ("missing", "drift", "no recipe", "stale"):
        return RED
    return DIM


def print_table(rows, header):
    widths = [max(len(str(row[index])) for row in [header] + rows) for index in range(len(header))]
    say("  ".join(title.ljust(widths[index]) for index, title in enumerate(header)))
    say("  ".join("-" * width for width in widths))
    for row in rows:
        cells = []
        for index, cell in enumerate(row):
            text = str(cell).ljust(widths[index])
            if index == len(row) - 1:
                text = state_colour(str(cell)) + text + INF
            cells.append(text)
        say("  ".join(cells))


def report_check(ctx, names):
    rows = []
    problems = []
    for name in names:
        dep = ctx.dep(name)
        state = dep_state(ctx, name)
        rows.append([name, dep.get("version") or "", dep.get("provider") or "", state])
        if state == "drift":
            problems.append(
                specmod.drift_message(
                    name, brew_version(ctx, dep["formula"]), dep.get("version"), ctx.overlay_file
                )
            )
        elif state == "no recipe":
            problems.append(
                'enabled {} dependency "{}" has no recipe in tools/deps/recipes.py'.format(
                    dep.get("provider"), name
                )
            )
        elif state == "stale":
            problems.append(
                "{} in the prefix was built from a different spec; re-run the driver".format(name)
            )
        elif state == "missing":
            problems.append("{} {} is not provisioned".format(name, dep.get("version") or ""))
    print_table(rows, ["name", "version", "provider", "state"])
    return problems


def report_list(ctx, names):
    rows = []
    for name in names:
        dep = ctx.dep(name)
        source = dep.get("formula") if dep.get("provider") == "brew" else dep.get("url")
        rows.append(
            [
                name,
                dep.get("version") or "",
                "yes" if dep.get("enabled") else "no",
                dep.get("provider") or "",
                source or "-",
            ]
        )
    print_table(rows, ["name", "version", "enabled", "provider", "source of truth"])


# ----------------------------------------------------------------------------------------------------------
# main


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Provision the dependency prefix declared by deps/<platform>.json.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Versions and features are never passed on the command line: edit the spec or the local overlay.",
    )
    parser.add_argument(
        "--spec",
        default=os.environ.get("OPENDCC_DEPS_SPEC"),
        help="base spec (default: deps/<platform>.json)",
    )
    parser.add_argument(
        "--config",
        default=os.environ.get("OPENDCC_DEPS_CONFIG"),
        help="user overlay (default: deps/<platform>.local.json)",
    )
    parser.add_argument(
        "--prefix",
        default=os.environ.get("OPENDCC_DEPS_DIR"),
        help="install prefix (default: <repo>/install_dir/deps)",
    )
    parser.add_argument("--check", action="store_true", help="merge, validate and resolve only")
    parser.add_argument("--list", action="store_true", help="list every dependency and its pin")
    parser.add_argument("--print-config", action="store_true", help="print the merged spec as JSON")
    parser.add_argument("--only", default="", help="comma separated subset to provision")
    parser.add_argument(
        "--force",
        action="append",
        default=[],
        help="rebuild even when the stamp matches (repeatable, comma separated)",
    )
    parser.add_argument(
        "--jobs", type=int, default=max(1, os.cpu_count() or 4), help="parallel build jobs"
    )
    parser.add_argument(
        "--update-lock",
        action="store_true",
        help="recompute and record sha256 pins for source archives",
    )
    return parser.parse_args(argv)


def check_toolchain():
    proc = run(["xcode-select", "-p"], check=False)
    if proc.returncode != 0:
        die("Xcode command line tools are required: run `xcode-select --install`")
    version = run(["xcodebuild", "-version"], check=False)
    if "CommandLineTools" in (version.stdout or ""):
        say(
            YELLOW
            + "warning: only the Command Line Tools are selected; a full Xcode is required for some SDKs"
            + INF
        )


def main(argv):
    args = parse_args(argv)
    repo = specmod.repo_root()
    if args.spec:
        spec_file = os.path.abspath(args.spec)
    else:
        spec_file = os.path.abspath(specmod.default_spec_path())
    if not os.path.exists(spec_file):
        die("no dependency spec at {}; pass --spec or add the file".format(specmod.rel(spec_file)))
    overlay_file = os.path.abspath(args.config or specmod.default_overlay_path(spec_file))

    merged, _, _ = specmod.resolve(spec_file, overlay_file)
    prefix = os.path.abspath(args.prefix or os.path.join(repo, "install_dir", "deps"))
    ctx = Ctx(repo, prefix, merged, spec_file, overlay_file, args.jobs)

    header = [
        "{}spec{}     {}".format(BOLD, INF, specmod.rel(spec_file)),
        "{}overlay{}  {}".format(
            BOLD,
            INF,
            specmod.rel(overlay_file)
            if os.path.exists(overlay_file)
            else "none ({} absent, ignored)".format(specmod.rel(overlay_file)),
        ),
        "{}prefix{}   {}".format(BOLD, INF, prefix),
    ]
    if args.print_config:
        # stdout stays machine readable so `--print-config | jq` works; context goes to stderr.
        sys.stderr.write("\n".join(header) + "\n")
        say(json.dumps(merged, indent=2))
        return 0
    for line in header:
        say(line)

    names = specmod.KNOWN_DEPS
    enabled = [name for name in names if ctx.dep(name).get("enabled")]

    if args.list:
        report_list(ctx, names)
        return 0

    if args.check:
        problems = report_check(ctx, names)
        if problems:
            say("")
            for problem in problems:
                say(RED + "  " + problem + INF)
            return 1
        say("")
        say(GREEN + "all enabled dependencies are provisioned" + INF)
        return 0

    check_toolchain()
    ctx.ensure_layout()

    only = [part.strip() for part in args.only.split(",") if part.strip()]
    forced = [entry.strip() for part in args.force for entry in part.split(",") if entry.strip()]
    for label, values in (("--only", only), ("--force", forced)):
        for value in values:
            if value not in specmod.KNOWN_DEPS:
                die('unknown dependency "{}" in {}'.format(value, label))

    targets = only or enabled
    if args.update_lock:
        say("")
        say(BOLD + "lock" + INF + ":")
        for name in targets:
            dep = ctx.dep(name)
            if dep.get("provider") in ("source", "headers"):
                download(ctx, name, dep, rehash=True)
        if ctx.lock_dirty:
            save_lock(ctx)
            info("updated {}".format(specmod.rel(lock_path(spec_file))))
            ctx.lock_dirty = False
        say("")

    # Bottles and the shared interpreter first: every source build links against them.
    brew_targets = [n for n in targets if ctx.dep(n).get("provider") == "brew"]
    source_targets = [n for n in targets if ctx.dep(n).get("provider") in ("source", "headers")]
    provision(ctx, brew_targets, forced)
    if (ctx.merged.get("ocio") or {}).get("url"):
        say(BOLD + "ocio config" + INF + ":")
        provision_ocio_config(ctx)
        say("")
    if not only or "python" in targets or "pyside" in targets or "usd" in targets:
        ensure_venv(ctx, force="venv" in forced)
        say("")
    provision(ctx, source_targets, forced)

    if ctx.lock_dirty:
        save_lock(ctx)
        info("recorded new pins in {}".format(specmod.rel(lock_path(spec_file))))

    info("wrote {}".format(specmod.rel(write_generated_cache(ctx))))

    incomplete = [
        name
        for name in enabled
        if dep_state(ctx, name) in ("missing", "drift", "stale", "no recipe")
    ]
    if incomplete:
        say("")
        if only:
            say(
                YELLOW
                + "  note: {} still not provisioned; a full run completes them".format(
                    ", ".join(incomplete)
                )
                + INF
            )
        else:
            for name in incomplete:
                say(RED + "  " + name + " is still not provisioned" + INF)
            return 1
    say("")
    say(GREEN + "dependency prefix is ready: " + prefix + INF)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except specmod.SpecError as error:
        say(RED + "dependency spec is not usable:" + INF)
        for problem in error.problems:
            say("  " + problem)
        sys.exit(1)
    except (ProvisionError, recipes.RecipeError) as error:
        say("")
        say(RED + str(error) + INF)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
