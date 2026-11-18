# Versions

`VERSIONS.md` is the only place dependency versions are declared. `pixi run plan` parses the
tables below and fails when a row, column or cell it needs is missing — it never falls back to
"whatever resolves today". Add a release here before building it.

- **Building against an existing OpenUSD** does not use the `OpenUSD releases` table: the stack
  is read out of that build (`pixi run probe -- --usd <prefix>`) and only `Build platform`
  applies.
- **Building OpenUSD from source** uses the release row plus `Build platform` to create the pixi
  environment that OpenUSD and OpenDCC are both built in.
- **A VFX Reference Platform year** (`pixi run plan -- --release 25.11 CY2025`) is a target for
  the VFX stack: it replaces the release row's version of every stack component the platform
  lists. `Build platform` outranks it, because it holds OpenDCC's own requirements (Qt, PySide,
  NumPy) and a calendar year cannot put the application on a Qt no channel publishes.
- **`OpenUSD tested versions` is a floor** on the result, whatever table supplied the version.
- **Source-built dependencies** are compiled once per build tree with that same environment.

Per dependency the plan layers the declarations, lowest precedence first — `OpenUSD releases` row,
VFX Reference Platform year, `Build platform` — applies the `OpenUSD tested versions` floor, and
puts `--pin`/`--python` on top. The plan report names the layer that decided every version, so
nothing is replaced silently.

## OpenUSD releases

The VFX stack each OpenUSD release is built and linked against. All rows point at one set of
channel packages on purpose: these libraries are ABI-coupled, so a row that mixes them is not a
row that builds.

| OpenUSD | Python | Boost | TBB     | OpenSubdiv | OpenImageIO | OpenColorIO | OpenEXR | Imath | MaterialX |
| ------- | ------ | ----- | ------- | ---------- | ----------- | ----------- | ------- | ----- | --------- |
| 26.08   | 3.12   | 1.88  | 2022.3  | 3.8        | 3.1         | 2.5         | 3.4     | 3.2   | 1.39      |
| 25.11   | 3.12   | 1.88  | 2022.3  | 3.8        | 3.1         | 2.5         | 3.4     | 3.2   | 1.39      |
| 25.08   | 3.12   | 1.88  | 2022.3  | 3.8        | 3.1         | 2.5         | 3.4     | 3.2   | 1.39      |

Notes on the pinned stack:

- **TBB is oneTBB 2022.3**, the version the GPU OpenSubdiv build requires. OpenUSD 25.08 and
  later select their oneTBB code path with `__has_include(<tbb/tbb_stddef.h>)`, so they build
  against oneTBB 2022 unpatched. OpenDCC's own `find_package(TBB)` reads `oneapi/tbb/version.h`,
  which oneTBB 2022.3 provides.
- **OpenSubdiv comes from the `opensubdiv-gpu` package**, not `opensubdiv`. OpenUSD's `hdSt`
  links `OpenSubdiv::osdGPU` whenever GPU support is on (the only mode that gives OpenDCC a
  render delegate), and the plain package is the CPU-only build: OpenUSD's configure then fails
  on the missing target. `opensubdiv-gpu` is the same 3.8 sources built with the GPU
  evaluators, and it is what pins TBB to 2022.3.
- **OpenImageIO stays on 3.1** because OpenShadingLanguage 1.15 (which OpenDCC links) is built
  against it. OpenImageIO 3.2 requires OpenColorIO 2.5 `>=2.5.1,<2.6` *and* OpenEXR 3.5, which
  no single channel build of OSL 1.15 accepts.
- **Qt is held at 6.11.0**: 6.11.1 regressed `QImage::toCGImage()` (QTBUG-147602) — the returned
  `CGImageFormat` holds a color space that is released before use — so any cursor whose image
  carries an ICC profile (the toolbar's resize handle, the wait cursor) aborts the application on
  the first hover. 6.11.0 predates that commit and is fixed in 6.11.2, but 6.11.2 cannot be
  installed next to the GPU OpenSubdiv build: its `qt6-multimedia` requires ffmpeg 9, whose
  conda builds require OpenVINO 2026.3, whose TBB floor of 2023 excludes the
  `opensubdiv-gpu` 3.8 build that pins TBB 2022.3. Revisit when OpenSubdiv's TBB pin moves.
- **Python is pinned exactly** whenever a specific OpenUSD build is in play: OpenDCC embeds
  Python and its bindings are ABI-tied to the interpreter OpenUSD's own bindings were built for.

## OpenUSD tested versions

The versions OpenUSD records as tested for each release tag, from the `Tested` table of
`https://github.com/PixarAnimationStudios/OpenUSD/blob/v<tag>/VERSIONS.md`. A **floor, never a
target**: no plan resolves a dependency below the version OpenUSD was tested against, and a plan
that has to raise one above another table's version says so in its report. Where OpenUSD's own
test platforms disagree (its table is per OS), the highest listed version is used; a cell states
the series when the tested versions differ only in patch.

| OpenUSD | Python | TBB    | OpenSubdiv | OpenImageIO | OpenColorIO | OpenEXR | MaterialX | OSL     | PySide |
| ------- | ------ | ------ | ---------- | ----------- | ----------- | ------- | --------- | ------- | ------ |
| 26.08   | 3.9    | 2021.9 | 3.6.1      | 2.5.16      | 2.4.2       | 3.1.13  | 1.39.5    | 1.13.11 | 6.3.1  |
| 25.11   | 3.9    | 2021.9 | 3.6.1      | 2.5.16      | 2.2.1       | 3.1.13  | 1.39.3    | 1.13.11 | 6.3.1  |
| 25.08   | 3.9    | 2021.9 | 3.6.0      | 2.5.16      | 2.2.1       | 3.1.13  | 1.39.3    | 1.13.11 | 6.3.1  |

Not rows here, on purpose: **Embree** (OpenUSD's `hdEmbree` links 4.x, OpenDCC itself links 3.x —
one row cannot gate both), **Ptex, Alembic, OpenVDB and Draco** (the OpenUSD build here switches
those plugins off), and the build tools OpenUSD lists (CMake, Flex, Bison, Doxygen, Graphviz,
Jinja2) — the `Build platform` versions are newer than what OpenUSD tested.

## VFX Reference Platform

The versions each VFX Reference Platform year requires,
`https://vfxplatform.com/#reference-platform`. Cells state the series the platform calls out; `-`
means the platform does not constrain that component.

`pixi run plan -- --release <tag> CY20xx` selects one column. The year is the **target for the
VFX stack**: it replaces the release row for every stack component it lists. `Build platform`
outranks it — OpenDCC's own Qt, PySide and NumPy are not downgraded by a calendar year — and the
plan report prints each component the year set, wanted and lost, so the resolution is visible
either way. The `OpenUSD tested versions` floor still applies on top of whatever the year sets.

These are the platforms as published, not as the channels here can install: those rebuild what
they target, so a year older than CY2026 selects builds that no longer exist (OpenColorIO 2.4,
OpenSubdiv 3.6, Qt 6.5, a Boost 1.85 compiled against an older ICU). That shows up in
`pixi install`, one package at a time, and `--pin` moves a component off the platform there.

| Component   | CY2027 | CY2026 | CY2025 | CY2024 |
| ----------- | ------ | ------ | ------ | ------ |
| Python      | 3.13   | 3.13   | 3.11   | 3.11   |
| Qt          | 6.8    | 6.8    | 6.5    | 6.5    |
| PySide      | 6.8    | 6.8    | 6.5    | 6.5    |
| Boost       | 1.91   | 1.88   | 1.85   | 1.82   |
| Imath       | 3.2    | 3.2    | 3.1    | 3.1    |
| NumPy       | 2.4    | 2.3    | 1.26   | 1.24   |
| oneTBB      | 2023   | 2022   | 2021   | -      |
| OpenColorIO | 2.6    | 2.5    | 2.4    | 2.3    |
| OpenEXR     | 3.5    | 3.4    | 3.3    | 3.2    |
| OpenSubdiv  | 3.8    | 3.7    | 3.6    | 3.6    |

CY2024 states Intel TBB 2020 Update 3, the legacy TBB. This build only uses oneTBB and
`opensubdiv-gpu` pins it, so TBB is left to the other tables there rather than pinned to a package
nothing can satisfy.

The platform's remaining components are either switched off in this OpenUSD build (Alembic,
OpenVDB, Ptex, Draco), not resolved by this build system (ACES is the `ocio-config` row below,
FBX and oneMKL are unused), or not a dependency version at all: the C++ standard and the
toolchain. The standard still comes from `cmake/defaults/CXXDefaults.cmake`, which compiles
OpenDCC as C++17 — what CY2025 requires, while CY2026 and later move to C++20.

## Build platform

Versions that do not follow the OpenUSD release. Same for every build on every platform, so a
build tree only depends on which OpenUSD it was pointed at. This is the lowest layer of the
resolution: a release row and a VFX Reference Platform year both replace entries here, which is
why the Qt pin below only holds when no platform year overrides it.

| Component | Version |
| --------- | ------- |
| Qt        | 6.11.0  |
| PySide    | 6.11.0  |
| Clang     | 23.1    |
| CMake     | 4.5     |
| Ninja     | 1.13    |
| GLEW      | 2.3     |
| ZeroMQ    | 4.3     |
| Eigen     | 5.0     |
| Graphviz  | 14.1    |
| doctest   | 2.5     |
| fmt       | 12.2    |
| six       | 1.17    |
| Pygments  | 2.20    |
| Qt.py     | 2.0     |
| NumPy     | 2.5     |
| Bullet    | 3.25    |
| Embree    | 3.13    |
| Embree 4  | 4.4     |
| pybind11  | 3.1     |
| OSL       | 1.15    |
| Jinja2    | 3.1     |

`Clang` is the libclang that the Shiboken generators link against; it comes from the same
pixi environment as PySide so the two always match. `Embree` stays on 3.x because OpenDCC's
`find_package(Embree 3)` asks for `embree3/rtcore.h`, while `Embree 4` is what an OpenUSD built
here needs for its `hdEmbree` plugin. They install different sonames (`libembree3`,
`libembree4`), so both can be present; an existing OpenUSD brings its own Embree 4. `OSL` is not part of the OpenUSD build
(`PXR_ENABLE_OSL_SUPPORT=OFF`) but OpenDCC links it, so it is pinned here. `fmt` is not linked:
spdlog is built with `SPDLOG_FMT_EXTERNAL` and compiled header-only, and the version matches the
fmt that OpenImageIO 3.1 vendors so a translation unit only ever holds one copy. `Jinja2` is a build
requirement of OpenUSD's `usdGenSchema`, which the build runs with the environment's python.

## Source-built dependencies

Pixi does not package these on every platform (the Qt Advanced Docking System and OpenMesh have
no `osx-arm64` build at all), so the build compiles them once into `<build>/deps`.

| Component | Version | Source |
| --------- | ------- | ------ |
| Qt Advanced Docking System | 4.4.1 | https://codeload.github.com/githubuser0xFFFF/Qt-Advanced-Docking-System/tar.gz/refs/tags/4.4.1 |
| sentry-native | 0.17.6 | https://github.com/getsentry/sentry-native/archive/refs/tags/0.17.6.tar.gz |
| OpenMesh | 9.0.0 | https://www.openmesh.org/media/Releases/9.0/OpenMesh-9.0.tar.gz |
| libigl | 2.6.0 | https://codeload.github.com/libigl/libigl/tar.gz/refs/tags/v2.6.0 |
| ocio-config | 4.0 | https://github.com/AcademySoftwareFoundation/OpenColorIO-Config-ACES/releases/download/v4.0.0/cg-config-v4.0.0_aces-v2.0_ocio-v2.5.ocio |

The OCIO row is not built: it is the ACES CG config the install ships as `ocio/config.ocio`, the
file OpenDCC's color management loads when `$OCIO` is not set. Without it the application falls
back to OpenColorIO's built-in legacy config and the viewport cannot build a display transform.

sentry-native is built with `SENTRY_BACKEND=none`: the crash reporter is off by default, and the
in-app reporter needs a crashpad build that no channel publishes (`DCC_BUILD_CRASH_REPORTER=ON`
with your own sentry).

## Platform status

| Platform | Build | Notes |
| -------- | ----- | ----- |
| macOS arm64 | verified | Xcode Command Line Tools provide clang; everything else is pixi. OpenUSD 25.11 built from source, OpenDCC configured, built, installed; 28 of 31 CTest tests pass (see BUILDING.md) |
| Linux x86_64 | expected, needs a machine | `gcc_linux-64`/`gxx_linux-64` 14 come from pixi |
| Windows x86_64 | expected, needs a machine | Visual Studio 2022 Build Tools (C++ workload) provide MSVC; everything else is pixi |
