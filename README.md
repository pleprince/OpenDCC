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
`deps/macos-arm64.json`; nothing is passed on a CMake command line. A gitignored overlay,
`deps/macos-arm64.local.json`, overrides any part of it for one machine.

```bash
# Prerequisites: Xcode command line tools, Homebrew, cmake >= 3.21, ninja.
python3 tools/deps/bootstrap.py            # provision everything enabled, write install_dir/deps/deps.generated.cmake
python3 tools/deps/bootstrap.py --check     # merge + validate + report, changes nothing (exit 1 when incomplete)
python3 tools/deps/bootstrap.py --list      # every dependency, its pin and where it comes from
python3 tools/deps/bootstrap.py --print-config   # the merged spec CMake will be built against

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
it in the overlay, which `CMakeUserPresets.json` points at (see `CMakeUserPresets.json.example`):

```json
{ "dependencies": { "openvdb": { "enabled": true },
                    "usd": { "features": { "openvdb": true } } } }
```

Re-run `bootstrap.py` afterwards. Source archives are pinned by sha256 in the tracked
`deps/macos-arm64.lock.json` (`--update-lock` refreshes the pins); each built dependency records what it was built
from in `install_dir/deps/stamps/<name>.json`, so editing a version or a feature rebuilds exactly that dependency.
Configure fails with an explicit message if the spec changed since the prefix was provisioned, so a stale
`deps.generated.cmake` cannot silently build against the wrong dependency set.
`Linux` and `Windows` are unaffected: the generated cache is only loaded when `OPENDCC_DEPS_DIR` is set.

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
