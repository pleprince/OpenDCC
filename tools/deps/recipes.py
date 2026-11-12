# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""Spec-driven build steps for source dependencies.

No version number appears in this file: everything that can vary comes from the spec, which is passed in as
``ctx`` (resolved paths) and the dependency's ``features`` map. Each recipe returns its own switches; the
driver adds the fixed ones (build type, install prefix, arch, policy floor, ``CMAKE_PREFIX_PATH``).
"""

import glob
import os


class RecipeError(Exception):
    """A dependency's source tree or build step cannot be used."""


# USD feature -> CMake switch(es). Verified against OpenUSD v25.08 cmake/defaults/Options.cmake. Two switches
# older docs list are gone in 25.08: PXR_USE_PYTHON_3 (Python 3 is the only interpreter now) and
# PXR_BUILD_OPENVDB_PLUGIN (folded into PXR_ENABLE_OPENVDB_SUPPORT).
USD_FEATURE_SWITCHES = {
    "imaging": ["PXR_BUILD_IMAGING"],
    "usd_imaging": ["PXR_BUILD_USD_IMAGING"],
    "usd_tools": ["PXR_BUILD_USD_TOOLS"],
    "usdview": ["PXR_BUILD_USDVIEW"],
    "python": ["PXR_ENABLE_PYTHON_SUPPORT"],
    "gl": ["PXR_ENABLE_GL_SUPPORT"],
    "metal": ["PXR_ENABLE_METAL_SUPPORT"],
    "openimageio": ["PXR_BUILD_OPENIMAGEIO_PLUGIN"],
    "opencolorio": ["PXR_BUILD_OPENCOLORIO_PLUGIN"],
    "hdf5": ["PXR_ENABLE_HDF5_SUPPORT"],
    "ptex": ["PXR_ENABLE_PTEX_SUPPORT"],
    "alembic": ["PXR_BUILD_ALEMBIC_PLUGIN"],
    "openvdb": ["PXR_ENABLE_OPENVDB_SUPPORT"],
    "embree": ["PXR_BUILD_EMBREE_PLUGIN"],
    "prman": ["PXR_BUILD_PRMAN_PLUGIN"],
    "materialx": ["PXR_ENABLE_MATERIALX_SUPPORT"],
    "draco": ["PXR_BUILD_DRACO_PLUGIN"],
    "osl": ["PXR_ENABLE_OSL_SUPPORT"],
    "tests": ["PXR_BUILD_TESTS"],
    "examples": ["PXR_BUILD_EXAMPLES"],
    "tutorials": ["PXR_BUILD_TUTORIALS"],
}

# usd.features.<feature> needs the matching dependency keg on CMAKE_PREFIX_PATH.
USD_FEATURE_KEGS = {
    "openimageio": "openimageio",
    "opencolorio": "opencolorio",
    "hdf5": "hdf5",
    "ptex": "ptex",
    "alembic": "alembic",
    "openvdb": "openvdb",
    "embree": "embree",
    "materialx": "materialx",
    "draco": "draco",
    "osl": "osl",
}


def common_cmake_args(ctx, requires):
    """Arguments every source recipe gets: release, our prefix, arm64, and the kegs it builds against."""
    prefix_path = [ctx.prefix] + [ctx.keg(name) for name in requires if name != "python"]
    return [
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INSTALL_PREFIX={}".format(ctx.prefix),
        "-DCMAKE_OSX_ARCHITECTURES={}".format(ctx.arch),
        # CMake 4 rejects cmake_minimum_required(<3.5), which every old dependency here still declares.
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
        "-DCMAKE_PREFIX_PATH={}".format(";".join(prefix_path)),
    ]


class Recipe:
    """A dependency built out of tree and installed into the prefix, or only extracted (headers)."""

    kind = "source"
    install_hint = ""
    # Files that prove the dependency is installed; any one existing is enough.
    markers = ()
    # Patches in tools/deps/patches applied with -p1 after extraction, in order.
    patches = ()

    def requires(self, features):
        return []

    def present(self, ctx):
        for pattern in self.markers:
            if glob.glob(os.path.join(ctx.prefix, pattern)):
                return True
        return False

    def cmake_args(self, features, ctx):
        return []

    def env(self, features, ctx):
        """Extra environment for every step (e.g. a tool directory on PATH)."""
        return {}

    def verify(self, src, features, ctx):
        """Check the extracted tree. Called after extraction, before any step runs."""

    def steps(self, src, build, features, ctx):
        """Build steps as ``(label, argv)``; environment comes from ``env()``. Must not touch the disk."""
        args = common_cmake_args(ctx, self.requires(features)) + self.cmake_args(features, ctx)
        return [
            ("configure", ["cmake", "-S", src, "-B", build, "-G", "Ninja"] + args),
            ("build", ["cmake", "--build", build, "-j", str(ctx.jobs)]),
            ("install", ["cmake", "--install", build]),
        ]


class EmbreeRecipe(Recipe):
    # embree 3 is required: FindEmbree.cmake and the mesh/point-cloud BVH code include embree3/rtcore.h.
    install_hint = "EMBREE_LOCATION points at the prefix."
    markers = ("lib/cmake/embree-*", "lib/libembree3*", "lib/libembree*.dylib")
    # Two dead friend operators print members QuadraticBezierCurve/PointMi no longer have; current clang
    # rejects the non-dependent lookup that older clang deferred.
    patches = ("embree-3.13.5-apple-clang.patch",)

    def cmake_args(self, features, ctx):
        return [
            "-DEMBREE_ISPC_SUPPORT=OFF",
            "-DEMBREE_TUTORIALS=OFF",
            "-DEMBREE_TASKING_SYSTEM=INTERNAL",
            "-DBUILD_SHARED_LIBS=ON",
        ]


class BulletRecipe(Recipe):
    # FindBullet3.cmake needs BulletRobotics plus the static libs directly in <root>/lib.
    install_hint = "BULLET_ROOT points at the prefix."
    markers = ("lib/libBulletRobotics.a", "lib/libBulletCollision.a")

    def steps(self, src, build, features, ctx):
        steps = super().steps(src, build, features, ctx)
        # VHACD is compiled into BulletRobotics, but bullet has no install rule for its public header, which
        # opendcc.usd_editor.bullet_physics includes as <VHACD.h>.
        include_dir = os.path.join(ctx.prefix, "include")
        steps.append(("make-include-dir", [ctx.cmake, "-E", "make_directory", include_dir]))
        steps.append(
            (
                "install-vhacd-header",
                [
                    ctx.cmake,
                    "-E",
                    "copy_if_different",
                    os.path.join(src, "Extras", "VHACD", "public", "VHACD.h"),
                    os.path.join(include_dir, "VHACD.h"),
                ],
            )
        )
        return steps

    def cmake_args(self, features, ctx):
        return [
            "-DBUILD_SHARED_LIBS=OFF",
            "-DBUILD_BULLET_ROBOTICS=ON",
            "-DBUILD_BULLET2_DEMOS=OFF",
            "-DBUILD_OPENGL3_DEMOS=OFF",
            "-DBUILD_CPU_DEMOS=OFF",
            "-DBUILD_UNIT_TESTS=OFF",
            "-DINSTALL_LIBS=ON",
        ]


class QtAdsRecipe(Recipe):
    # Installs lib/cmake/qtadvanceddocking-qt6 exporting ads::qtadvanceddocking-qt6.
    install_hint = "qtadvanceddocking-qt6 config lands in <prefix>/lib/cmake."
    markers = ("lib/cmake/qtadvanceddocking-qt6/*.cmake",)
    # Upstream links Qt6::GuiPrivate on every Qt6 platform, but only linux/ sources need it.
    patches = ("qtads-4.4.1-qt-private.patch",)

    def requires(self, features):
        return ["qtbase"]

    def cmake_args(self, features, ctx):
        return [
            # The tarball has no git index, which upstream falls back to for its version; ADS_VERSION skips that.
            "-DADS_VERSION={}".format(ctx.version_of("qtads")),
            "-DBUILD_EXAMPLES=OFF",
            "-DBUILD_STATIC=OFF",
            "-DCMAKE_INSTALL_LIBDIR=lib",
        ]


class MaterialXRecipe(Recipe):
    """MaterialX has no Homebrew formula, and USD's MaterialX support links its shared libraries directly."""

    install_hint = "MaterialXConfig.cmake lands in <prefix>/lib/cmake/MaterialX."
    markers = ("lib/cmake/MaterialX/MaterialXConfig.cmake",)
    # Storm's Metal generator includes the shared shader library and then emits the node implementations that live
    # in that same library as function blocks, so the text lands twice and Metal rejects the program with
    # "class member cannot be redeclared". The patch skips a block already emitted verbatim.
    patches = ("materialx-1.39.3-include-dedupe.patch",)

    def cmake_args(self, features, ctx):
        return [
            # Shared, because hdSt and usdMtlx link it; the generators USD does not call are off to keep the build
            # small, and every optional dependency (Python, OIIO, OCIO, viewer) is off so nothing else is pulled in.
            "-DMATERIALX_BUILD_SHARED_LIBS=ON",
            "-DMATERIALX_BUILD_MONOLITHIC=ON",
            "-DMATERIALX_BUILD_PYTHON=OFF",
            "-DMATERIALX_INSTALL_PYTHON=OFF",
            "-DMATERIALX_BUILD_VIEWER=OFF",
            "-DMATERIALX_BUILD_GRAPH_EDITOR=OFF",
            "-DMATERIALX_BUILD_TESTS=OFF",
            "-DMATERIALX_BUILD_OIIO=OFF",
            "-DMATERIALX_BUILD_OCIO=OFF",
            "-DMATERIALX_BUILD_OSOS=OFF",
        ]


class LibiglRecipe(Recipe):
    """Header-only: nothing is built, the tree is only checked and exported as IGL_ROOT."""

    kind = "headers"
    install_hint = "IGL_ROOT points at <prefix>/src/libigl."
    header_probe = "include/igl/igl_inline.h"
    markers = ("src/libigl/include/igl/igl_inline.h",)

    def verify(self, src, features, ctx):
        if not os.path.exists(os.path.join(src, self.header_probe)):
            raise RecipeError("{} is missing from the libigl archive".format(self.header_probe))

    def steps(self, src, build, features, ctx):
        return []


class UsdRecipe(Recipe):
    install_hint = "USD_ROOT points at the prefix; python modules land in <prefix>/lib/python."
    # oneTBB 2023 moved the version macros behind a header blocked_range.h no longer pulls in, and dropped the
    # header hdEmbree still includes for them.
    patches = (
        "usd-25.08-onetbb-version.patch",
        "usd-25.08-hdembree-onetbb.patch",
    )
    markers = ("lib/cmake/pxr/pxrConfig.cmake", "lib/python/pxr/__init__.py")

    def requires(self, features):
        # Every dependency USD links against has to come from the pinned kegs: with only some of them on
        # CMAKE_PREFIX_PATH, USD's configure falls through to whatever install the machine happens to expose (here a
        # pre-existing OpenSubdiv 3.6.1), bakes that @rpath into its libraries and the render delegate then fails to
        # load at runtime.
        deps = ["python", "boost", "tbb", "opensubdiv", "imath", "openexr"]
        for feature, dep in USD_FEATURE_KEGS.items():
            if (features or {}).get(feature):
                deps.append(dep)
        if (features or {}).get("openimageio"):
            # OpenImageIO's headers include <fmt/format.h>; the keg has to be on the include path.
            deps.append("fmt")
        return deps

    def cmake_args(self, features, ctx):
        features = features or {}
        args = [
            "-DPython3_EXECUTABLE={}".format(ctx.python_exe),
            "-DTBB_ROOT={}".format(ctx.keg("tbb")),
        ]
        if features.get("openimageio"):
            # OpenImageIO's public headers include <fmt/format.h> and the keg does not export that dependency.
            args.append("-DCMAKE_CXX_FLAGS=-isystem {}/include".format(ctx.keg("fmt")))
        # Every switch is emitted explicitly, ON or OFF, so a cached build tree cannot keep an old feature set.
        for feature, switches in USD_FEATURE_SWITCHES.items():
            value = "ON" if features.get(feature) else "OFF"
            for switch in switches:
                args.append("-D{0}={1}".format(switch, value))
        return args


def qt_install_prefix(ctx):
    """The Qt prefix whose lib/cmake can resolve every module, private packages included.

    Homebrew splits Qt into kegs and Qt resolves a component relative to the prefix its Qt6Config.cmake lives
    under, so pointing at the qtbase keg alone makes e.g. Qt6QmlPrivate unfindable; the Homebrew prefix links
    every module's config directory into one lib/cmake.
    """
    keg = ctx.keg("qtbase")
    candidate = os.path.dirname(os.path.dirname(keg))
    if os.path.exists(os.path.join(candidate, "lib", "cmake", "Qt6", "Qt6Config.cmake")):
        return candidate
    return keg


class PySideRecipe(Recipe):
    """Built with its own distutils front end: Homebrew's bottle targets a newer interpreter than the spec's.

    ``setup.py install`` is the documented flow and installs PySide6, shiboken6 and their typesystems into the
    venv, which is exactly what find_package(PySide6) and the typesystem substitutions need.
    """

    install_hint = "PySide6/shiboken6 land in <prefix>/venv/lib/pythonX.Y/site-packages."
    # shiboken parses with Homebrew libclang, which needs the SDK sysroot spelled out on macOS.
    patches = (
        "pyside-6.12.0-macos-sysroot.patch",
        "pyside-6.12.0-module-symbol-visibility.patch",
    )
    markers = (
        "venv/lib/python*/site-packages/PySide6/typesystems/typesystem_core.xml",
        "venv/bin/shiboken6",
    )

    def requires(self, features):
        return ["qtbase", "qtshadertools", "qtdeclarative", "qtquick3d", "python", "llvm"]

    def env(self, features, ctx):
        # setup.py needs qtpaths6 on PATH, libclang via LLVM_INSTALL_DIR, and every Qt module keg on
        # CMAKE_PREFIX_PATH: Homebrew splits Qt into kegs, so a sibling module's private package (Qt6QmlPrivate
        # for the Qml bindings) is only found through the prefix path.
        qt_kegs = [ctx.keg(name) for name in self.requires(features) if name.startswith("qt")]
        sdkroot = getattr(ctx, "sdkroot", "")
        env = {
            "LLVM_INSTALL_DIR": ctx.keg("llvm"),
            "CMAKE_PREFIX_PATH": ";".join(qt_kegs),
            "PATH": ctx.prepend_paths(
                [
                    ctx.keg("llvm") + "/bin",
                    ctx.keg("qtbase") + "/bin",
                    qt_install_prefix(ctx) + "/bin",
                ]
            ),
        }
        if sdkroot:
            # shiboken parses with libclang from Homebrew, which does not know the SDK sysroot the way Apple's
            # clang does; without it the bundled libc++ headers fail on missing <math.h> macros.
            env["SDKROOT"] = sdkroot
        return env

    def steps(self, src, build, features, ctx):
        return [
            (
                "install",
                [
                    ctx.python_exe,
                    os.path.join(src, "setup.py"),
                    "install",
                    "--qt-target-path={}".format(qt_install_prefix(ctx)),
                    # The app links libshiboken, and Shiboken6's CMake target re-exports Py_LIMITED_API through
                    # INTERFACE_COMPILE_DEFINITIONS. USD's vendored boost.python needs the full CPython object
                    # types, so build PySide for the full API of the pinned interpreter.
                    "--limited-api=no",
                    "--no-qt-tools",
                    "--parallel={}".format(ctx.jobs),
                    "--cmake={}".format(ctx.cmake),
                ],
            )
        ]


RECIPES = {
    "embree": EmbreeRecipe(),
    "bullet": BulletRecipe(),
    "qtads": QtAdsRecipe(),
    "libigl": LibiglRecipe(),
    "materialx": MaterialXRecipe(),
    "usd": UsdRecipe(),
    "pyside": PySideRecipe(),
}
