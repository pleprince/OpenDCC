# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# Dependency spec for macOS on arm64: the only place dependency versions and feature switches are declared.
# Provisioned by `cmake --preset macos-arm64-deps`, which merges this file with the gitignored overlay
# deps/macos-arm64.local.cmake (same functions, any subset of fields), validates the result and builds whatever is
# missing into install_dir/deps.
#
# Nothing here is a build-system configuration: the driver translates this into install_dir/deps/deps.generated.cmake,
# which is the only thing the application build reads.
#
# To build against a USD that was not provisioned here, point the overlay at it
# (deps/macos-arm64.local.cmake); CMAKE_CURRENT_LIST_DIR is the overlay's own directory:
#   opendcc_deps_spec_dependency(usd PROVIDER external PREFIX "${CMAKE_CURRENT_LIST_DIR}/../install_dir/deps")
# `cmake --preset macos-arm64-deps` then adopts that installation's release, feature set and Python/TBB/OpenSubdiv
# pins instead of building a USD, and prints what it adopted. If the path is not there, the spec falls back to the
# provider this file declares for it (source), so USD is downloaded and built instead of failing. Add ALIGN OFF to
# verify the spec against the installation instead, and to require it.

opendcc_deps_spec_begin(PLATFORM macos-arm64 SCHEMA 1)

opendcc_deps_spec_python(VERSION 3.12 PROVIDER brew FORMULA python@3.12)

opendcc_deps_spec_qt(VERSION 6.12.0 PYSIDE 6.12.0)

# The colour config the application loads at runtime; sha256 is pinned because it is downloaded, not built.
opendcc_deps_spec_ocio(
    CONFIG_VERSION 4.0.0
    URL "https://github.com/AcademySoftwareFoundation/OpenColorIO-Config-ACES/releases/download/v4.0.0/cg-config-v4.0.0_aces-v2.0_ocio-v2.5.ocio"
    SHA256 "9e3ec773a7fbc0bb6666e428dedd8ccec4f59b8b6d40506c825cc7a8c02ff2ff")

# Feature switches of the application build. One-to-one with the CMake options of the same meaning.
opendcc_deps_spec_opendcc(
    TESTS=ON
    I18N=ON
    CRASH_REPORTER=OFF
    RENDER_VIEW=ON
    NODE_EDITOR=ON
    BULLET_PHYSICS=ON
    ARNOLD_SUPPORT=OFF
    CYCLES_SUPPORT=OFF
    RENDERMAN_SUPPORT=OFF
    USE_PTEX=OFF
    USE_HOUDINI=OFF
    USE_KATANA=OFF)

# Homebrew dependencies: `VERSION` is the keg the prefix was provisioned with, `EXPECT` the range the application
# is known to work with. CMAKE_VARS are the finder roots the generated cache exports.
opendcc_deps_spec_dependency(
    boost
    ENABLED ON
    PROVIDER brew
    FORMULA boost
    VERSION 1.92.0
    EXPECT ">=1.85"
    CMAKE_VARS "BOOST_ROOT=@FORMULA@")
opendcc_deps_spec_dependency(eigen ENABLED ON PROVIDER brew FORMULA eigen VERSION 5.0.1 EXPECT ">=3.4")
opendcc_deps_spec_dependency(
    tbb
    ENABLED ON
    PROVIDER brew
    FORMULA onetbb
    VERSION 2023.2.0
    EXPECT ">=2021"
    CMAKE_VARS "TBB_ROOT_DIR=@FORMULA@")
opendcc_deps_spec_dependency(
    glew
    ENABLED ON
    PROVIDER brew
    FORMULA glew
    VERSION 2.3.1
    EXPECT ">=2.1"
    CMAKE_VARS "GLEW_LOCATION=@FORMULA@")
opendcc_deps_spec_dependency(
    zmq
    ENABLED ON
    PROVIDER brew
    FORMULA zeromq
    VERSION 4.3.5
    EXPECT ">=4.3"
    CMAKE_VARS "ZMQ_ROOT=@FORMULA@")
opendcc_deps_spec_dependency(
    graphviz
    ENABLED ON
    PROVIDER brew
    FORMULA graphviz
    VERSION any
    EXPECT any
    CMAKE_VARS "GRAPHVIZ_ROOT=@FORMULA@")
opendcc_deps_spec_dependency(doctest ENABLED ON PROVIDER brew FORMULA doctest VERSION 2.5.3 EXPECT ">=2.4")
opendcc_deps_spec_dependency(
    openmesh
    ENABLED ON
    PROVIDER brew
    FORMULA open-mesh
    VERSION 11.0.0
    EXPECT ">=9"
    CMAKE_VARS "OPENMESH_ROOT=@FORMULA@")
opendcc_deps_spec_dependency(
    opensubdiv
    ENABLED ON
    PROVIDER brew
    FORMULA opensubdiv
    VERSION 3.8.0
    EXPECT ">=3.5"
    CMAKE_VARS "OPENSUBDIV_DIR=@FORMULA@")
opendcc_deps_spec_dependency(
    openimageio
    ENABLED ON
    PROVIDER brew
    FORMULA openimageio
    VERSION 3.2.2
    EXPECT ">=2.4"
    CMAKE_VARS "OIIO_LOCATION=@FORMULA@")
opendcc_deps_spec_dependency(fmt ENABLED ON PROVIDER brew FORMULA fmt VERSION 12.2.1 EXPECT ">=9")
opendcc_deps_spec_dependency(
    opencolorio
    ENABLED ON
    PROVIDER brew
    FORMULA opencolorio
    VERSION 2.6.0
    EXPECT ">=2.2"
    CMAKE_VARS "OCIO_LOCATION=@FORMULA@")
opendcc_deps_spec_dependency(imath ENABLED ON PROVIDER brew FORMULA imath VERSION 3.2.3 EXPECT ">=3.1")
opendcc_deps_spec_dependency(openexr ENABLED ON PROVIDER brew FORMULA openexr VERSION 3.5.3 EXPECT ">=3.1")
opendcc_deps_spec_dependency(sentry ENABLED ON PROVIDER brew FORMULA sentry-native VERSION 0.17.6 EXPECT ">=0.6")
opendcc_deps_spec_dependency(qtbase ENABLED ON PROVIDER brew FORMULA qtbase VERSION 6.12.0 EXPECT "==6.12")
opendcc_deps_spec_dependency(qtmultimedia ENABLED ON PROVIDER brew FORMULA qtmultimedia VERSION 6.12.0 EXPECT "==6.12")
opendcc_deps_spec_dependency(qtsvg ENABLED ON PROVIDER brew FORMULA qtsvg VERSION 6.12.0 EXPECT "==6.12")
opendcc_deps_spec_dependency(qttools ENABLED ON PROVIDER brew FORMULA qttools VERSION 6.12.0 EXPECT "==6.12")
opendcc_deps_spec_dependency(
    qtshadertools ENABLED ON PROVIDER brew FORMULA qtshadertools VERSION 6.12.0 EXPECT "==6.12")
opendcc_deps_spec_dependency(
    qtdeclarative ENABLED ON PROVIDER brew FORMULA qtdeclarative VERSION 6.12.0 EXPECT "==6.12")
opendcc_deps_spec_dependency(
    qtquick3d ENABLED ON PROVIDER brew FORMULA qtquick3d VERSION 6.12.0 EXPECT "==6.12")
opendcc_deps_spec_dependency(
    llvm
    ENABLED ON
    PROVIDER brew
    FORMULA llvm@20
    VERSION 20.1.8
    EXPECT "==20"
    CMAKE_VARS "SHIBOKEN_CLANG_INSTALL_DIR=@FORMULA@")
opendcc_deps_spec_dependency(
    python
    ENABLED ON
    PROVIDER brew
    FORMULA python@3.12
    VERSION 3.12.16
    EXPECT "==3.12"
    CMAKE_VARS "PYTHON_EXECUTABLE=@PREFIX@/venv/bin/python3"
               "Python3_EXECUTABLE=@PREFIX@/venv/bin/python3"
               "Python_EXECUTABLE=@PREFIX@/venv/bin/python3")
opendcc_deps_spec_dependency(pybind11 ENABLED ON PROVIDER brew FORMULA pybind11 VERSION 3.1.0 EXPECT ">=3.0")

# Source-built dependencies. No sha256 pin here: the tracked lock file records the bytes, and
# OPENDCC_DEPS_UPDATE_LOCK=1 refreshes it.
opendcc_deps_spec_dependency(
    embree
    ENABLED ON
    PROVIDER source
    VERSION 3.13.5
    EXPECT "==3.13"
    URL "https://github.com/RenderKit/embree/archive/refs/tags/v3.13.5.tar.gz"
    STRIP 1
    CMAKE_VARS "EMBREE_LOCATION=@PREFIX@")
opendcc_deps_spec_dependency(
    bullet
    ENABLED ON
    PROVIDER source
    VERSION 3.25
    EXPECT ">=3.20"
    URL "https://codeload.github.com/bulletphysics/bullet3/tar.gz/refs/tags/3.25"
    STRIP 1
    CMAKE_VARS "BULLET_ROOT=@PREFIX@")
opendcc_deps_spec_dependency(
    qtads
    ENABLED ON
    PROVIDER source
    VERSION 4.4.1
    EXPECT ">=4.0"
    URL "https://codeload.github.com/githubuser0xFFFF/Qt-Advanced-Docking-System/tar.gz/refs/tags/4.4.1"
    STRIP 1)
opendcc_deps_spec_dependency(
    libigl
    ENABLED ON
    PROVIDER headers
    VERSION v2.6.0
    EXPECT ">=2.0"
    URL "https://codeload.github.com/libigl/libigl/tar.gz/refs/tags/v2.6.0"
    STRIP 1
    CMAKE_VARS "IGL_ROOT=@PREFIX@/src/libigl")
opendcc_deps_spec_dependency(
    usd
    ENABLED ON
    PROVIDER source
    VERSION 25.08
    EXPECT ">=25.02"
    URL "https://codeload.github.com/PixarAnimationStudios/OpenUSD/tar.gz/refs/tags/v25.08"
    STRIP 1
    FEATURES
    imaging=ON
    usd_imaging=ON
    usd_tools=ON
    usdview=OFF
    python=ON
    gl=ON
    metal=ON
    openimageio=ON
    opencolorio=ON
    hdf5=OFF
    ptex=OFF
    alembic=OFF
    openvdb=OFF
    embree=ON
    prman=OFF
    materialx=ON
    draco=OFF
    osl=OFF
    tests=OFF
    examples=OFF
    tutorials=OFF
    CMAKE_VARS "USD_ROOT=@PREFIX@")
opendcc_deps_spec_dependency(
    pyside
    ENABLED ON
    PROVIDER source
    VERSION 6.12.0
    EXPECT "==6.12"
    URL "https://download.qt.io/official_releases/QtForPython/pyside6/PySide6-6.12.0-src/pyside-setup-everywhere-src-6.12.0.tar.xz"
    SHA256 "099c1a597cf33c1b000e11cf68a0b82d216fb802bf81726efc720394f10c7751"
    STRIP 1)

# Optional dependencies, off by default. Turning one on here (or in the overlay) is enough for the driver and the
# validator to accept it, as long as whatever needs it is enabled too.
opendcc_deps_spec_dependency(
    alembic
    ENABLED OFF
    PROVIDER brew
    FORMULA alembic
    VERSION 1.8.12
    EXPECT ">=1.7"
    CMAKE_VARS "Alembic_ROOT=@FORMULA@" "ALEMBIC_DIR=@FORMULA@")
opendcc_deps_spec_dependency(
    openvdb
    ENABLED OFF
    PROVIDER brew
    FORMULA openvdb
    VERSION 14.0.0
    EXPECT ">=10"
    CMAKE_VARS "OPENVDB_LOCATION=@FORMULA@" "OPENVDB_ROOT=@FORMULA@")
opendcc_deps_spec_dependency(
    ptex
    ENABLED OFF
    PROVIDER brew
    FORMULA ptex
    VERSION 2.5.4
    EXPECT ">=2.3"
    CMAKE_VARS "PTEX_LOCATION=@FORMULA@")
opendcc_deps_spec_dependency(
    hdf5
    ENABLED OFF
    PROVIDER brew
    FORMULA hdf5
    VERSION 2.2.0
    EXPECT ">=1.10"
    CMAKE_VARS "HDF5_ROOT=@FORMULA@")
opendcc_deps_spec_dependency(partio ENABLED OFF PROVIDER brew FORMULA partio VERSION 1.20.0 EXPECT ">=1.10")
opendcc_deps_spec_dependency(draco ENABLED OFF PROVIDER brew FORMULA draco VERSION 1.5.9 EXPECT ">=1.4")
opendcc_deps_spec_dependency(
    materialx
    ENABLED ON
    PROVIDER source
    VERSION 1.39.3
    EXPECT "==1.39"
    URL "https://codeload.github.com/materialx/MaterialX/tar.gz/refs/tags/v1.39.3"
    STRIP 1)

# Manual dependencies: the driver never installs them; a CMAKE_VARS entry marked @MANUAL@ only tells the user what
# find_package() needs to be pointed at.
opendcc_deps_spec_dependency(skia ENABLED OFF PROVIDER manual VERSION any EXPECT any)
opendcc_deps_spec_dependency(
    opentimelineio
    ENABLED OFF
    PROVIDER manual
    VERSION any
    EXPECT any
    CMAKE_VARS "OpenTimelineIO_ROOT=@MANUAL@")
opendcc_deps_spec_dependency(arnold ENABLED OFF PROVIDER manual VERSION any EXPECT any)
opendcc_deps_spec_dependency(cycles ENABLED OFF PROVIDER manual VERSION any EXPECT any)
opendcc_deps_spec_dependency(
    osl
    ENABLED OFF
    PROVIDER manual
    VERSION any
    EXPECT any
    CMAKE_VARS "OSL_ROOT=@MANUAL@")
