# OpenDCC

### 🔀 About This Fork

This is an **independent, pure open-source fork** of the [original OpenDCC project](https://github.com/shapefx/OpenDCC), started by one of the original authors.

**Goals of this fork:**
- 📜 **Apache 2.0 licensed** — Maintains the same permissive open-source license
- 🌍 **Easier OSS contribution** — Streamlined workflows for community contributors
- ⚡ **Upgrades and improvements** — Modernization and enhancements across the codebase
- 📦 **Prebuilt binaries** — Downloadable releases to lower the barrier to entry

We welcome contributions, feedback, and collaboration from the broader community!

---

### Overview

**OpenDCC** is an Apache 2.0 licensed, open-source Digital Content Creation (DCC) application framework for building modular, production-grade 3D tools. It combines a flexible, plugin-driven architecture with an industry-standard Qt-based interface, embedded Python scripting, [OpenUSD](https://github.com/PixarAnimationStudios/OpenUSD) and Hydra integration.

OpenDCC is built for pipeline developers, technical artists, and studios who need custom tools that fit their workflow—not the other way around.

🛠️ This project is a work in progress and is actively developed.

### 🎨 Industry-Standard Artist Frontend, Developer-Controlled Backend

OpenDCC is built around a core idea:

> **Provide an artist-friendly, industry-standard frontend that feels like home—while giving developers full control over the backend.**

Artists interact with a familiar UI environment—for example, viewport manipulators—while developers can swap or extend the underlying scene system, computation logic, or renderer. This separation ensures artists can focus on creativity while technical teams retain complete control over data and integration.

### 💡 Pursuing an Industry-Standard UI

OpenDCC aims to deliver a user experience that feels familiar to artists across the industry. By using Qt, PySide, and [Advanced Docking System (ADS)](https://github.com/githubuser0xFFFF/Qt-Advanced-Docking-System), it provides a clean, industry-standard interface that reflects the interaction paradigms professionals already know—multi-pane layouts and scriptable panels. Our goal is to offer the stability and predictability artists expect, while remaining fully customizable underneath.

### 🔌 Powered by [OpenUSD](https://github.com/PixarAnimationStudios/OpenUSD) and Hydra

OpenDCC integrates Pixar's [OpenUSD](https://github.com/PixarAnimationStudios/OpenUSD) and Hydra as its primary scene and rendering backends. This provides powerful native support for real-time stage manipulation, variant sets, layering, point instancing, and Hydra-based selection. Hydra allows interactive rendering via multiple render delegates, and is fully compatible with complex production scenes. These technologies are tightly integrated into OpenDCC and serve as the core, non-optional foundations of the current OpenDCC architecture.

As part of our philosophy, we aim to minimize patches or modifications to OpenUSD itself. This ensures that studios can easily swap in their own forks of the USD library with minimal integration overhead, supporting long-term maintainability and compatibility across pipeline environments.

### ✅ Conforms to VFX Reference Platform

OpenDCC conforms to the [VFX Reference Platform](https://vfxplatform.com/), ensuring compatibility with standard production tools, libraries, and Python versions widely used in the visual effects and animation industry.

---

### ✨ Key Features

- **Application Framework for Making Your Own 3D Tools**
- **Native OpenUSD Editing**
- **Hydra Rendering and Viewport**
- **Viewport Tools System**
- **Industry-Standard Manipulators via `pxr.Gf`**
- **Edit UsdGeomXformable Using Manipulators**
- **Edit UsdGeomPointBased Using Manipulators with Soft Selection**
- **Hydra Selection for Points, Edges, Faces, Instances**
- **Hydra Soft Selection**
- **Common VFX Widgets (Timeline, Shelf, etc.)**
- **Integrated Python Script Editor**
- **Command System with Undo/Redo and Python Command Record**
- **Preferences and User Settings System**
- **App Config System Using `toml` Files**
- **Integrated Logging Framework**
- **USD Delta IPC Syncing**
- **Standalone Render View**
- **Hydra CLI Rendering**
- **Qt Node Editor Framework**
- **UsdShade Node Editor**
- **Explicit Plugin Packaging via `package.toml`**
- **Pybind11 and Shiboken Bindings**
- *and more...*

---

### 🧩 Included Tools & Plugins

| Plugin                  | Description                                                                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Animation Curves        | AnimX-based curve editing with timeline and keyframe support                                                                           |
| AnimX Graph Editor UI   | Graph view of AnimX connections for visualizing animation flow                                                                         |
| AnimX Channel Editor UI | Channel-based editor for managing AnimX animation channels                                                                             |
| USD UV Editor           | Interactive UV layout tool for USD meshes                                                                                              |
| Bullet Physics Tool     | Experimental physics layout tool for scene blocking and rigid body interaction using Bullet                                            |
| Sculpt Tool             | Point-based sculpting for USD geometry                                                                                                 |
| Point Instancer Tool    | Author and edit USD point instancers                                                                                                   |
| Bezier Tool             | Draw and edit USD Bezier curves with interactive handles                                                                               |
| Paint Primvar Tool      | Paint and visualize arbitrary USD primvars directly on geometry                                                                        |
| Paint Texture Tool      | Paint image-based textures into USD shader networks or layered materials                                                               |
| HydraOps                | Procedural lighting and scene processing system built on HydraSceneIndex                                                               |
| Render View             | Included standalone viewer with support for OIIO-backed image data, OCIO color transforms, and ZMQ-based protocol for image transport |

---

### 🖥️ Platform & Build Support

| Platform | Status         |
| -------- | -------------- |
| Linux    | ✅ Supported    |
| Windows  | ✅ Supported    |
| macOS    | ⚠️ In Progress |

---

### ⚙️ Building

#### macOS (arm64)

Dependency versions and dependency features live in exactly one tracked file per platform,
`deps/macos-arm64.cmake`; nothing is passed on a CMake command line. A gitignored overlay,
`deps/macos-arm64.local.cmake`, overrides any part of it for one machine.

```bash
# Prerequisites: Xcode command line tools, Homebrew, cmake >= 3.21, ninja, patch.
cmake --preset macos-arm64-deps                # provision everything enabled, write install_dir/deps/deps.generated.cmake
cmake --preset macos-arm64-deps-check          # merge + validate + report, changes nothing (exit 1 when incomplete)
cmake --preset macos-arm64-deps-list           # every dependency, its pin and where it comes from
cmake --preset macos-arm64-deps-print-config   # the merged spec CMake will be built against

cmake --preset macos-arm64-release
cmake --build --preset macos-arm64-release
cmake --install build/macos-arm64-release
ctest --preset macos-arm64-release --output-on-failure

# launch the installed application (the POSIX counterpart of opendcc.bat)
install_dir/macos-arm64/opendcc
install_dir/macos-arm64/opendcc --script path/to/script.py
```

Dependencies come from a prebuilt Homebrew bottle when the keg matches the pinned version and are built from
source into `install_dir/deps` otherwise. To change a version or switch a feature, edit the spec — or override
it in the overlay, which `CMakeUserPresets.json` points at (see `CMakeUserPresets.json.example`). The overlay
calls the same spec functions as the base file and only states what changes; `CMAKE_VARS` and `FEATURES` merge
per key, every other field replaces:

```cmake
# deps/macos-arm64.local.cmake
opendcc_deps_spec_dependency(openvdb ENABLED ON)
opendcc_deps_spec_opendcc(USE_PTEX=ON)
opendcc_deps_spec_dependency(usd FEATURES openvdb=ON ptex=ON)
```

Re-run `cmake --preset macos-arm64-deps` afterwards; source dependencies are built in dependency order, so a
fresh prefix completes in one run. Source archives are pinned by sha256 in the tracked
`deps/macos-arm64.lock.cmake`; each built dependency records what it was built from in
`install_dir/deps/stamps/<name>.cmake`, so editing a version or a feature rebuilds exactly that dependency.
Configure fails with an explicit message if the spec changed since the prefix was provisioned, so a stale
`deps.generated.cmake` cannot silently build against the wrong dependency set.

##### Using a USD build you already have

Any dependency can be declared `PROVIDER external` with an absolute `PREFIX`. For USD the driver does not check
that installation against the spec and complain: by default it reads the installation and **adopts** what it
finds, so the whole build — provisioning, generated cache, application — follows that USD:

```cmake
# deps/macos-arm64.local.cmake
opendcc_deps_spec_dependency(usd PROVIDER external PREFIX "${CMAKE_CURRENT_LIST_DIR}/../my-usd-build")
```

`cmake --preset macos-arm64-deps` then aligns the merged spec and reports every value it changed, instead of
building a USD:

```
external dependencies:
  usd.VERSION 25.08 -> 25.11
  python.VERSION 3.12.16 -> 3.11 (the external USD was built against 3.11.15)
  python.EXPECT "==3.12" -> "any" (the external build defines the version)
  python VERSION 3.12 -> 3.11 (the venv is recreated and everything built against it rebuilds)
  python FORMULA python@3.12 -> python@3.11
  opensubdiv.VERSION 3.8.0 kept (the external USD requires >= 3.6.1)
  usd.features.usdview OFF -> ON
  tbb brew -> external /path/to/my-usd-build (the external USD is built against tbb 2020.3 and its headers
      instantiate that API)
  tbb.VERSION 2023.2.0 -> 2020.3
  tbb.EXPECT ">=2021" -> "any" (the external build defines the version)
```

What is read from the installation:

- **Release**: `PXR_MINOR_VERSION`/`PXR_PATCH_VERSION` from `include/pxr/pxr.h`, adopted as `usd.VERSION`.
- **Pins it was built against**: the `find_dependency()` lines in its `pxrConfig.cmake`. A version there is a
  declaration of what that build linked, and the three are not the same kind of constraint:
  `find_dependency(Python3 "3.11.15" EXACT)` names its interpreter, so the `python` dependency and the venv
  follow it (major.minor only — the patch is whatever keg brew has); `find_dependency(TBB 2020.3 CONFIG)` and
  `find_dependency(OpenSubdiv 3.6.1 CONFIG)` are **minimums**, so a spec that already provisions a newer keg
  keeps it and only an older pin is raised. The check applies the same rule — a spec pin *older* than the
  recorded minimum is the failure, a newer one is not. brew cannot downgrade, and the driver refuses to try: a pin
  below the installed keg fails with both versions and what to change.
- **The TBB it ships**: a USD built without a TBB config package (`PXR_FIND_TBB_IN_CONFIG "OFF"`, the default case
  for a self-contained install) carries its own TBB and points `TBB::tbb` at it, which makes that line above dead
  text. Then TBB is not a minimum at all: `pxr`'s public headers instantiate the TBB API of the build they came
  from, and TBB has no compatibility across the oneTBB boundary (`tbb::task` is gone from oneTBB 2021), so the
  `tbb` dependency is moved to that installation — `PROVIDER external`, its prefix, its version read from
  `include/oneapi/tbb/version.h` or `include/tbb/tbb_stddef.h`. This is the one case where alignment replaces a
  dependency the spec provisions instead of adjusting a version.
- **Feature set**: one decisive artifact per switch — `lib/`, `plugin/usd/`, `lib/python/pxr/` — adopted as
  `usd.features.*`. `opencolorio`, `ptex`, `openvdb`, `hdf5`, `tests`, `examples` and `tutorials` leave no such
  artifact, so the spec's value stands and the report says the switch cannot be verified.

Adopting a version has consequences the driver then carries out: a different keg version is provisioned, a
different Python minor recreates the venv (and rebuilds every source dependency that builds against it, which is
why the interpreter is part of their build identity), and an adopted version outside a declared `EXPECT` range
drops that range to `any` — a range says what this build supports, and an installation we do not build is not
something we can claim to support.

If the installation is not available at all — the directory is missing, or it carries no `include/pxr/pxr.h` /
`lib/lib*usd_usd.*` — that is not an error: the driver falls back to the provider this platform declared
for the dependency before the overlay, so USD is downloaded and built into the prefix and the run continues.

```
external dependencies:
  usd: /path/to/my-usd-build does not exist; provisioning it with provider source instead
```

An installation that exists but cannot be read is a hard error, and so is one that does not agree with itself:

- **Layout**: `pxrConfig.cmake` (root, `lib/cmake/pxr` or `cmake`) and `bin/usdGenSchema` must exist; without the
  two markers above the dependency is unavailable rather than broken, and falls back as described.
- **Linkage**: every `libusd_*` and `plugin/usd/*` binary may only reference system libraries, libraries private
  to the external prefix, the embedded Python, or a library an enabled dependency provides under the same soname
  (`libOpenImageIO.3.2.dylib` in both places is fine; a differing soname is not).
- **Import**: the modules this build uses must import with the prefix's interpreter.

`ALIGN OFF` on the declaration changes both halves: the spec stays authoritative, nothing is adopted, and the
installation is *required* — a missing one fails instead of falling back. Every disagreement then fails
`macos-arm64-deps-check`, which is what you want in CI when the point is to prove a machine's USD is the pinned
one.

Either way that prefix is authoritative once in place: `deps.generated.cmake` pins `USD_ROOT`,
`USD_INCLUDE_DIR`, `USD_LIBRARY_DIR`, `USD_CONFIG_FILE` and `USD_GENSCHEMA_SCRIPT` with `FORCE`, so an existing
build directory cannot keep the previous USD, and the external `lib` directory comes first on the install rpath —
both the build tree and the installed application link and load it. Deleting the overlay and re-running
`cmake --preset macos-arm64-deps` restores the provisioned paths, including the rpath entry.

That authority is bounded to what USD needs. An external USD is a *complete* prefix — it carries the OpenImageIO,
OpenEXR, Imath, OpenColorIO, OpenSubdiv and TBB it was built with — so letting it answer for those would silently
link libraries the spec does not pin, and compiling its headers against the provisioned copies builds a
source-level mismatch (OpenImageIO 2.5 headers, 3.2 library) that fails at compile time or, worse, loads. Two rules
keep the two sides apart:

- The external prefix is last in `CMAKE_PREFIX_PATH`, after everything the spec provisions, so a `find_package()`
  only falls back to it for a package nothing provides. USD itself does not depend on that order: its paths are
  forced.
- `deps.generated.cmake` exports `DCC_DEPS_INCLUDE_DIRS` — the include roots of the provisioned dependencies, then
  the external prefixes' — and the application adds them as system includes before any library's exported include
  directories. That is what makes `<OpenImageIO/...>` the OpenImageIO that is linked, and `<tbb/...>` the TBB the
  adopted `tbb` dependency placed second.

USD's own binaries resolve their dependencies by `@rpath` inside that prefix, which the install rpath keeps ahead
of the dependency prefix. The exceptions where a provisioned dependency cannot win are handled by alignment rather
than by ordering — the TBB above, and the `Imath_DIR`/`MaterialX_DIR` that `pxrConfig.cmake` hardcodes to its
install.

Environment selectors, for one-off runs (never cached):

| Variable | Effect |
| ---------------------------- | ------------------------------------------------------------------------------------- |
| `OPENDCC_DEPS_DIR` | prefix to provision (default `install_dir/deps`) |
| `OPENDCC_DEPS_SPEC` | spec file to use (default `deps/<platform>.cmake`) |
| `OPENDCC_DEPS_CONFIG` | overlay file to merge (default `deps/<platform>.local.cmake`) |
| `OPENDCC_DEPS_ONLY` | comma separated subset to provision |
| `OPENDCC_DEPS_FORCE` | comma separated subset to rebuild even when up to date (`venv` included) |
| `OPENDCC_DEPS_JOBS` | parallel build jobs (default: core count) |
| `OPENDCC_DEPS_UPDATE_LOCK` | `1` recomputes and records the source archive pins in the lock file |

`macos-arm64-deps-print-config` writes the merged spec to stdout, but a configure pass also prints CMake's own
status lines; pipe it through script mode when you want nothing but JSON:

```bash
cmake -DDEPS_MODE=print-config -P cmake/deps/CMakeLists.txt | python3 -m json.tool
```

`Linux` and `Windows` are unaffected: the generated cache is only loaded when `OPENDCC_DEPS_DIR` is set, and
neither platform has a spec yet.

#### Linux / Windows

This section is under active development.

---

### 📚 Documentation (Work in Progress)

Documentation is currently **not available**. Please explore the source code for usage examples.

---

### 🤝 Contributing (Work in Progress)

We welcome contributions from the community! Contribution guidelines and setup instructions are under active development. In the meantime, feel free to open issues, submit pull requests, or share feedback.

---

### 📄 License

Licensed under the **Apache 2.0 License**. See [LICENSE.txt](LICENSE.txt).

See [THIRD_PARTY_LICENSES.txt](THIRD_PARTY_LICENSES.txt) for license information about portions of OpenDCC that have been imported from other projects.
