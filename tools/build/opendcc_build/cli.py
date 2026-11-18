# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""Command line used by the pixi tasks (see pixi.toml and BUILDING.md)."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

if __package__ in (None, ""):  # executed as tools/build/opendcc-build
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from . import cmake_build
from . import pixi
from . import plan as planner
from . import probe as usd_probe
from . import sources
from . import state
from . import usd_build
from . import versions as versions_mod

ROOT = Path(__file__).resolve().parents[3]


def main(argv: list[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (
        planner.PlanError,
        usd_probe.ProbeError,
        pixi.PixiError,
        cmake_build.BuildError,
        sources.SourceError,
        state.StateError,
        usd_build.UsdBuildError,
        versions_mod.VersionsError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="opendcc-build",
        description="pixi-driven OpenDCC build (run through `pixi run <task> -- <args>`)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("bootstrap", help="install pixi for the current user if it is missing").set_defaults(
        func=_bootstrap
    )

    probe = sub.add_parser("probe", help="report what an OpenUSD build provides")
    probe.add_argument("--usd", required=True, help="OpenUSD install prefix")
    probe.add_argument("--json", action="store_true", help="print the raw probe result")
    probe.set_defaults(func=_probe)

    plan = sub.add_parser(
        "plan",
        help="extract the dependency set, create and install the pixi environment",
    )
    _target_arguments(plan)
    plan.add_argument(
        "--pin",
        action="append",
        default=[],
        metavar="NAME=VERSION",
        help="override one dependency version (repeatable), e.g. --pin tbb=2021.12",
    )
    plan.add_argument(
        "--option",
        action="append",
        default=[],
        metavar="DCC_OPTION=VALUE",
        help="override a CMake option of the opendcc build (repeatable)",
    )
    plan.set_defaults(func=_plan)

    deps = sub.add_parser("deps", help="build the dependencies pixi does not package")
    _build_argument(deps)
    deps.set_defaults(func=_deps)

    usd = sub.add_parser("usd", help="build OpenUSD from a release tag")
    _target_arguments(usd)
    usd.add_argument("-j", "--jobs", type=int, help="parallel compile jobs")
    usd.set_defaults(func=_usd)

    configure = sub.add_parser("configure", help="configure the opendcc build")
    _build_argument(configure)
    configure.add_argument(
        "--cmake-arg",
        action="append",
        default=[],
        metavar="ARG",
        help="extra argument passed to cmake (repeatable)",
    )
    configure.set_defaults(func=_configure)

    build = sub.add_parser("build", help="compile opendcc")
    _build_argument(build)
    build.add_argument("-j", "--jobs", type=int, help="parallel compile jobs")
    build.add_argument("--target", help="build one target")
    build.set_defaults(func=_build)

    install = sub.add_parser("install", help="install opendcc into install_dir/<slug>")
    _build_argument(install)
    install.set_defaults(func=_install)

    test = sub.add_parser("test", help="run the ctest suite")
    _build_argument(test)
    test.add_argument(
        "--ctest-arg",
        action="append",
        default=[],
        metavar="ARG",
        help="extra argument passed to ctest (repeatable), e.g. --ctest-arg -E --ctest-arg viewport",
    )
    test.set_defaults(func=_test)

    all_cmd = sub.add_parser(
        "all", help="plan, dependencies, OpenUSD (when --release), configure, build, install"
    )
    _target_arguments(all_cmd)
    all_cmd.add_argument("-j", "--jobs", type=int, help="parallel compile jobs")
    all_cmd.add_argument("--no-tests", action="store_true", help="skip the ctest run")
    all_cmd.add_argument(
        "--pin", action="append", default=[], metavar="NAME=VERSION", help=argparse.SUPPRESS
    )
    all_cmd.add_argument(
        "--option", action="append", default=[], metavar="DCC_OPTION=VALUE", help=argparse.SUPPRESS
    )
    all_cmd.set_defaults(func=_all)

    clean = sub.add_parser("clean", help="remove a build tree")
    _build_argument(clean)
    clean.add_argument(
        "--keep-env", action="store_true", help="keep the pixi environment and deps prefix"
    )
    clean.set_defaults(func=_clean)

    return parser


def _target_arguments(parser: argparse.ArgumentParser) -> None:
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--usd", help="OpenUSD install prefix to build against")
    group.add_argument("--release", help="OpenUSD release tag to build from source, e.g. 25.11")


def _build_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--build",
        metavar="SLUG",
        help="build tree to use (default: the only one under build/)",
    )


# --------------------------------------------------------------------------------------------
# commands


def _bootstrap(_args: argparse.Namespace) -> int:
    executable = pixi.ensure(verbose=True)
    print(f"pixi {pixi.version(executable)} at {executable} ({pixi.platform_key()})")
    print("next: pixi run plan -- --usd <OpenUSD prefix>")
    return 0


def _probe(args: argparse.Namespace) -> int:
    result = usd_probe.probe(Path(args.usd))
    if args.json:
        print(json.dumps(result.to_json(), indent=2, sort_keys=True))
        return 0
    _print_table(
        [("OpenUSD", result.version), ("pxr", result.pxr_version), ("prefix", str(result.prefix)),
         ("python", result.python or "unknown"),
         ("python bindings", "yes" if result.has_python_bindings else "no"),
         ("internal boost.python", "yes" if result.internal_boost_python else "no")],
        ("property", "value"),
    )
    print()
    if result.bundled:
        _print_table(sorted(result.bundled.items()), ("dependency", "version"))
    else:
        print("this OpenUSD build carries no third-party dependency configs of its own")
    problems = usd_probe.validate(result)
    for problem in problems:
        print(f"warning: {problem}", file=sys.stderr)
    return 0


def _plan(args: argparse.Namespace) -> int:
    plan = _make_and_install(args)
    _report(plan)
    return 0


def _deps(args: argparse.Namespace) -> int:
    plan, _ = _load(args.build)
    versions = _versions()
    sources.provision(plan, versions)
    print(f"source dependencies are in {plan.deps_prefix}")
    return 0


def _usd(args: argparse.Namespace) -> int:
    plan = _make_and_install(args)
    _report(plan)
    sources.provision(plan, _versions())
    prefix = usd_build.build(plan, _versions(), jobs=args.jobs)
    _record_built_usd(plan, prefix)
    print(f"OpenUSD {plan.release} installed at {prefix}")
    return 0


def _configure(args: argparse.Namespace) -> int:
    plan, _ = _load(args.build)
    cmake_build.configure(plan, extra=args.cmake_arg)
    print(f"build tree: {plan.cmake_dir}")
    return 0


def _build(args: argparse.Namespace) -> int:
    plan, _ = _load(args.build)
    cmake_build.build(plan, jobs=args.jobs, target=args.target)
    return 0


def _install(args: argparse.Namespace) -> int:
    plan, _ = _load(args.build)
    cmake_build.install(plan, _versions())
    print(f"installed into {plan.install_dir}")
    return 0


def _test(args: argparse.Namespace) -> int:
    plan, _ = _load(args.build)
    cmake_build.test(plan, extra=args.ctest_arg)
    return 0


def _all(args: argparse.Namespace) -> int:
    plan = _make_and_install(args)
    _report(plan)
    sources.provision(plan, _versions())

    if plan.from_source:
        prefix = usd_build.build(plan, _versions(), jobs=args.jobs)
        _record_built_usd(plan, prefix)

    cmake_build.configure(plan)
    cmake_build.build(plan, jobs=args.jobs)
    cmake_build.install(plan, _versions())
    print(f"installed into {plan.install_dir}", flush=True)
    if not args.no_tests:
        _report_tests(plan)
    return 0


def _clean(args: argparse.Namespace) -> int:
    plan, state_file = _load(args.build)
    if args.keep_env:
        for path in (plan.cmake_dir, plan.install_dir):
            shutil.rmtree(path, ignore_errors=True)
        state_file.unlink(missing_ok=True)
        print(f"removed build tree and install prefix of {plan.slug} (kept {plan.env_dir.name}/)")
        return 0
    shutil.rmtree(plan.build_dir, ignore_errors=True)
    shutil.rmtree(plan.install_dir, ignore_errors=True)
    print(f"removed {plan.build_dir} and {plan.install_dir}")
    return 0


# --------------------------------------------------------------------------------------------
# shared steps


def _versions() -> versions_mod.Versions:
    path = ROOT / "VERSIONS.md"
    if not path.is_file():
        raise versions_mod.VersionsError(f"{path} is missing; it declares every dependency version")
    return versions_mod.parse(path)


def _make_and_install(args: argparse.Namespace) -> planner.Plan:
    versions = _versions()
    options: dict[str, str] = {}
    for item in getattr(args, "option", []) or []:
        key, _, value = item.partition("=")
        if not key or not value:
            raise planner.PlanError(f"--option needs NAME=VALUE, got {item!r}")
        options[key] = value
    pins: dict[str, str] = {}
    for item in getattr(args, "pin", []) or []:
        key, _, value = item.partition("=")
        if not key or not value:
            raise planner.PlanError(f"--pin needs NAME=VERSION, got {item!r}")
        pins[key] = value

    pixi.ensure()
    plan = planner.make_plan(
        ROOT,
        versions,
        usd=Path(args.usd) if args.usd else None,
        release=args.release,
        options=options,
        pin_overrides=pins,
    )
    plan.env_dir.mkdir(parents=True, exist_ok=True)
    plan.manifest.write_text(planner.render_manifest(plan))
    pixi.install(plan.manifest)
    planner.check_python_abi(plan)
    state.save(plan)
    return plan


def _load(slug: str | None) -> tuple[planner.Plan, Path]:
    if slug:
        return state.load(ROOT / "build" / slug)
    return state.load(state.find(ROOT))


def _record_built_usd(plan: planner.Plan, prefix: Path) -> None:
    """Re-probe the USD we just built so the state and the report show its real versions."""
    result = usd_probe.probe(prefix)
    plan.probe = result
    plan.usd_prefix = prefix
    for warning in usd_probe.validate(result):
        plan.warnings.append(warning)
    drift = [
        f"{name}: VERSIONS.md {plan.resolved.get(name, '?')} vs USD {version}"
        for name, version in result.bundled.items()
        if name in plan.resolved and not version.startswith(plan.resolved[name].rstrip(".*"))
    ]
    plan.warnings.extend(f"OpenUSD disagrees with VERSIONS.md: {row}" for row in drift)
    planner.check_python_abi(plan)
    state.save(plan)


def _report(plan: planner.Plan) -> None:
    print()
    _print_table(
        [
            ("platform", plan.platform),
            ("build tree", str(plan.build_dir)),
            ("OpenUSD", f"{plan.release} ({'from source' if plan.from_source else plan.usd_prefix})"),
            ("environment", str(plan.env_dir)),
            ("install prefix", str(plan.install_dir)),
        ],
        ("", ""),
    )
    print()
    _print_table(
        planner.describe(plan), ("dependency", "provider", "version", "origin")
    )
    print()
    rows = planner.verify(plan)
    _print_table(rows, ("dependency", "provider", "wanted", "installed", "status"))
    mismatches = [row for row in rows if row[4] == "mismatch"]
    for warning in plan.warnings:
        print(f"warning: {warning}")
    if mismatches:
        names = ", ".join(f"{row[0]} ({row[2]} != {row[3]})" for row in mismatches)
        raise planner.PlanError(
            f"the installed environment does not match what this build was pinned to: {names}"
        )


def _report_tests(plan: planner.Plan) -> None:
    try:
        cmake_build.test(plan)
    except (cmake_build.BuildError, pixi.PixiError) as error:
        print(f"warning: ctest failed: {error}", file=sys.stderr)


def _print_table(rows, headers: tuple[str, ...]) -> None:
    body = [[str(cell) for cell in row] for row in rows]
    widths = [len(head) for head in headers]
    for row in body:
        for index, cell in enumerate(row):
            if index < len(widths):
                widths[index] = max(widths[index], len(cell))
    header_line = "  ".join(head.ljust(widths[i]) for i, head in enumerate(headers)).rstrip()
    print(header_line)
    print("  ".join("-" * width for width in widths))
    for row in body:
        print("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)).rstrip())
