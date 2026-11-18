# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""Build OpenUSD from a release tag with the pixi environment of that release.

This is the "from scratch" path: the release row in VERSIONS.md decides the stack, pixi installs
it, and OpenUSD is configured against exactly those libraries. The result is then probed like any
other USD installation, so the opendcc build itself has one code path.
"""

from __future__ import annotations

from pathlib import Path

from . import pixi
from .cmake_build import toolchain_environment
from .plan import Plan
from .sources import download, extract
from .versions import SourceComponent, Versions

USD_URL = "https://codeload.github.com/PixarAnimationStudios/OpenUSD/tar.gz/refs/tags/{tag}"


class UsdBuildError(RuntimeError):
    pass


def build(plan: Plan, versions: Versions, jobs: int | None = None, verbose: bool = True) -> Path:
    """Configure, build and install OpenUSD into the plan's USD prefix."""
    if plan.probe is not None:
        raise UsdBuildError("this plan already links an existing OpenUSD build")
    tag = plan.release
    prefix = plan.usd_dir
    stamp = prefix / f".opendcc-{tag}-installed"
    if stamp.is_file():
        if verbose:
            print(f"OpenUSD {tag} already built at {prefix}", flush=True)
        return prefix

    component = SourceComponent(
        name="usd", version=tag, url=USD_URL.format(tag=f"v{tag}")
    )
    archive = download(component, plan.root, verbose)
    source_dir = plan.build_dir / "src" / f"OpenUSD-{tag}"
    extract(archive, source_dir, strip=1)

    cmake = [
        "cmake",
        "-S",
        str(source_dir),
        "-B",
        str(prefix),
        "-G",
        "Ninja",
        "-DCMAKE_BUILD_TYPE=Release",
        f"-DCMAKE_INSTALL_PREFIX={prefix}",
        f"-DCMAKE_PREFIX_PATH={plan.env_cmake_prefix}",
        f"-DPython3_EXECUTABLE={plan.python}",
        f"-DBOOST_ROOT={plan.env_cmake_prefix}",
        f"-DTBB_ROOT_DIR={plan.env_cmake_prefix}",
        f"-DOIIO_LOCATION={plan.env_cmake_prefix}",
        f"-DOCIO_LOCATION={plan.env_cmake_prefix}",
        f"-DOPENSUBDIV_DIR={plan.env_cmake_prefix}",
        f"-DEMBREE_LOCATION={plan.env_cmake_prefix}",
    ]
    cmake += _options(plan.platform)
    env = toolchain_environment()
    pixi.run(plan.manifest, cmake, env=env, verbose=verbose)

    build_cmd = ["cmake", "--build", str(prefix)]
    if jobs:
        build_cmd += ["--parallel", str(jobs)]
    pixi.run(plan.manifest, build_cmd, env=env, verbose=verbose)
    pixi.run(plan.manifest, ["cmake", "--install", str(prefix)], env=env, verbose=verbose)

    if not (prefix / "pxrConfig.cmake").is_file():
        raise UsdBuildError(f"OpenUSD install left no pxrConfig.cmake in {prefix}")
    # pxrConfig.cmake alone does not prove a finished build: configure writes it into the build
    # tree, so an interrupted `cmake --build` would look installed and be skipped next time.
    stamp.write_text(f"OpenUSD {tag}\n")
    return prefix


def _options(platform: str) -> list[str]:
    """PXR_ switches opendcc needs. Anything else is left at the OpenUSD default."""
    options = {
        "PXR_BUILD_MONOLITHIC": "OFF",
        "PXR_BUILD_IMAGING": "ON",
        "PXR_BUILD_USD_IMAGING": "ON",
        "PXR_BUILD_USD_TOOLS": "ON",
        "PXR_BUILD_USDVIEW": "OFF",
        "PXR_BUILD_EXAMPLES": "OFF",
        "PXR_BUILD_TUTORIALS": "OFF",
        "PXR_BUILD_TESTS": "OFF",
        "PXR_BUILD_DOCUMENTATION": "OFF",
        "PXR_ENABLE_PYTHON_SUPPORT": "ON",
        "PXR_ENABLE_GL_SUPPORT": "ON",
        "PXR_BUILD_EMBREE_PLUGIN": "ON",
        "PXR_BUILD_OPENIMAGEIO_PLUGIN": "ON",
        "PXR_BUILD_OPENCOLORIO_PLUGIN": "ON",
        "PXR_ENABLE_MATERIALX_SUPPORT": "ON",
        "PXR_BUILD_ALEMBIC_PLUGIN": "OFF",
        "PXR_ENABLE_HDF5_SUPPORT": "OFF",
        "PXR_ENABLE_OSL_SUPPORT": "OFF",
        "PXR_ENABLE_OPENVDB_SUPPORT": "OFF",
        "PXR_ENABLE_PTEX_SUPPORT": "OFF",
        "PXR_BUILD_DRACO_PLUGIN": "OFF",
        "PXR_ENABLE_PRECOMPILED_HEADERS": "OFF",
        "BUILD_SHARED_LIBS": "ON",
    }
    if platform.startswith("osx"):
        options["PXR_ENABLE_METAL_SUPPORT"] = "ON"
    else:
        options["PXR_ENABLE_METAL_SUPPORT"] = "OFF"
        options["PXR_ENABLE_VULKAN_SUPPORT"] = "OFF"
    return [f"-D{key}={value}" for key, value in options.items()]
