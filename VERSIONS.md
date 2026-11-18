# Versions

`VERSIONS.md` is the only place dependency versions are declared. `pixi run plan` parses the
tables below and fails when a row, column or cell it needs is missing — it never falls back to
"whatever resolves today". Add a release here before building it.

- **Building against an existing OpenUSD** does not use the `OpenUSD releases` table: the stack
  is read out of that build (`pixi run probe -- --usd <prefix>`) and only `Build platform`
  applies.
- **Building OpenUSD from source** uses the release row plus `Build platform` to create the pixi
  environment that OpenUSD and OpenDCC are both built in.
- **Source-built dependencies** are compiled once per build tree with that same environment.

## OpenUSD releases

The VFX stack each OpenUSD release is built and linked against. All rows point at one set of
channel packages on purpose: these libraries are ABI-coupled, so a row that mixes them is not a
row that builds.

| OpenUSD | Python | Boost | TBB | OpenSubdiv | OpenImageIO | OpenColorIO | OpenEXR | Imath | MaterialX |
| ------- | ------ | ----- | --- | ---------- | ----------- | ---------- | ------- | ----- | --------- |
| 26.08   | 3.12   | 1.88  | 2022.3  | 3.8 | 3.1 | 2.5 | 3.4 | 3.2 | 1.39 |
| 25.11   | 3.12   | 1.88  | 2022.3  | 3.8 | 3.1 | 2.5 | 3.4 | 3.2 | 1.39 |
| 25.08   | 3.12   | 1.88  | 2022.3  | 3.8 | 3.1 | 2.5 | 3.4 | 3.2 | 1.39 |

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
- **Python is pinned exactly** whenever a specific OpenUSD build is in play: OpenDCC embeds
  Python and its bindings are ABI-tied to the interpreter OpenUSD's own bindings were built for.

## Build platform

Versions that do not follow the OpenUSD release. Same for every build on every platform, so a
build tree only depends on which OpenUSD it was pointed at.

| Component | Version |
| --------- | ------- |
| Qt        | 6.11    |
| PySide    | 6.11    |
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

sentry-native is built with `SENTRY_BACKEND=none`: the crash reporter is off by default, and the
in-app reporter needs a crashpad build that no channel publishes (`DCC_BUILD_CRASH_REPORTER=ON`
with your own sentry).

## Platform status

| Platform | Build | Notes |
| -------- | ----- | ----- |
| macOS arm64 | verified | Xcode Command Line Tools provide clang; everything else is pixi. OpenUSD 25.11 built from source, OpenDCC configured, built, installed; 28 of 31 CTest tests pass (see BUILDING.md) |
| Linux x86_64 | expected, needs a machine | `gcc_linux-64`/`gxx_linux-64` 14 come from pixi |
| Windows x86_64 | expected, needs a machine | Visual Studio 2022 Build Tools (C++ workload) provide MSVC; everything else is pixi |
