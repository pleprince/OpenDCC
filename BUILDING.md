# Building OpenDCC

OpenDCC is built with [pixi](https://github.com/prefix-dev/pixi). pixi provides the compiler
runtime, Qt/PySide, OpenUSD's dependencies and every other third-party package; CMake only ever
sees a fully resolved environment, never a "find it somewhere on the system".

Two things are fixed by design:

- **Every dependency version comes from [`VERSIONS.md`](VERSIONS.md).** Nothing floats. A build
  either has a version for a dependency or refuses to start.
- **Every build tree is bound to one OpenUSD.** Either you build OpenUSD from a release tag (the
  dependency stack comes from `VERSIONS.md`), or you point the build at an existing OpenUSD
  installation (the dependency stack is read out of that installation).

## Requirements

| Platform | Needs |
| -------- | ----- |
| macOS arm64 | Xcode Command Line Tools (`xcode-select --install`). Everything else is pixi |
| Linux x86_64 | Nothing but pixi: `gcc`/`g++` 14 come from the environment |
| Windows x86_64 | Visual Studio 2022 with the *Desktop development with C++* workload (or *Build Tools for Visual Studio 2022* with the same workload). Everything else is pixi |

Python 3.11+ only matters for the helper script that installs pixi; after that every python is
the one in the build environment.

## Install pixi

`pixi` installs for the current user, no root:

```sh
python3 tools/build/opendcc-build bootstrap
```

That is the same as running `curl -fsSL https://pixi.sh/install.sh | bash` and restarting the
shell; on Windows it runs `irm https://pixi.sh/install.ps1 | iex`. The build system calls it
automatically if `pixi` is missing, so `pixi run …` from an already-working checkout is enough.

## Build OpenUSD and OpenDCC from scratch

```sh
pixi run all -- --release 25.11          # 25.11 is a row in VERSIONS.md
```

This resolves the release row, creates `build/osx-arm64-usd25.11-src/env/`, compiles OpenUSD
25.11 with that environment, compiles OpenDCC against the OpenUSD it just built, installs into
`install_dir/osx-arm64-usd25.11-src/` and runs ctest.

Run the steps separately to iterate:

```sh
pixi run plan      -- --release 25.11    # create/refresh the environment, print the plan
pixi run usd       -- --release 25.11    # build OpenUSD only
pixi run configure                       # cmake configure (uses the last plan)
pixi run build     -- -j 10              # cmake build
pixi run install
pixi run test                            # ctest in the build tree
```

## Build against an existing OpenUSD

```sh
pixi run plan -- --usd /opt/usd/25.11
```

`--usd` is an OpenUSD install prefix: the directory that contains `pxrConfig.cmake`. The build
then

1. reads the release, the Python version and the dependency versions out of that installation
   (`pixi run probe -- --usd <prefix>` prints the same information);
2. links every dependency OpenUSD carries **from the OpenUSD prefix**, so OpenDCC and OpenUSD
   share one copy of Imath, OpenEXR, OpenImageIO, OpenColorIO, OpenSubdiv, MaterialX, boost and
   TBB instead of two ABI-incompatible ones;
3. asks pixi for everything OpenUSD does not carry (Qt, PySide, Shiboken, GLEW, ZeroMQ, Eigen,
   Graphviz, doctest, Embree, Bullet, OSL, pybind11, jinja2) and pins the Python interpreter to
   the exact version OpenUSD recorded;
4. verifies the installed environment against the probe and refuses to configure on a mismatch.

### The one hard requirement: OpenUSD's Python

OpenDCC embeds Python, and an OpenUSD built with Python support links the interpreter it was
configured against. A process cannot hold two libpython images, so the OpenUSD you point at must
be importable by the environment's interpreter. The build proves this by importing `pxr` with the
environment's python and fails early with an explanation when it cannot:

```
error: this OpenUSD build's python bindings cannot be imported by
  …/env/.pixi/envs/default/bin/python (OpenUSD was built against
  /opt/homebrew/opt/python@3.11/bin/python3.11, which links its own libpython; a process cannot
  hold two). Build OpenUSD with this build system instead, which makes both sides use one
  interpreter: `pixi run all -- --release 25.11`.
```

OpenUSD builds that are compatible out of the box are the ones this build system produces
(`pixi run usd -- --release <tag>`), and builds made against the same interpreter as the pixi
environment — for example a stack built against conda's `python` from the same environment.

## Tasks

| Task | What it does |
| ---- | ------------ |
| `pixi run bootstrap` | install pixi for the current user if needed |
| `pixi run probe -- --usd <prefix>` | report an OpenUSD build: version, Python, bundled dependencies |
| `pixi run plan -- (--usd <prefix> \| --release <tag>)` | extract the dependency set, write and install the environment, print the plan, verify it |
| `pixi run deps` | build the dependencies pixi does not package (Qt Advanced Docking System, sentry-native, OpenMesh, libigl) |
| `pixi run usd -- --release <tag>` | build OpenUSD from source into the build tree |
| `pixi run configure` / `build` / `install` / `test` | the opendcc CMake build |
| `pixi run all -- (--usd <prefix> \| --release <tag>)` | everything above in order |
| `pixi run clean` | remove a build tree (`--keep-env` keeps the environment and deps) |

Every task that needs a build tree uses the only one under `build/`; with several, pass
`--build <slug>`. Task arguments go after `--`.

Overrides for one-off experiments:

```sh
pixi run plan -- --release 25.11 --pin tbb=2021.12 --option DCC_BUILD_TESTS=OFF
```

`--pin` changes a pixi package version (the reason is printed in the plan), `--option` changes a
CMake option of the opendcc build. Permanent changes belong in `VERSIONS.md` or in the defaults
in `tools/build/opendcc_build/plan.py`.

## What a build tree looks like

```
build/<slug>/
  env/pixi.toml          generated manifest: the exact environment for this build
  env/.pixi/envs/default the environment itself
  deps/                  source-built dependencies (Qt ADS, sentry, OpenMesh, libigl)
  usd/                   OpenUSD built from source, when --release was used
  src/                   unpacked sources of the above
  cmake/                 the CMake build tree (compile_commands.json lives here)
  state.json             what this build tree was made from
install_dir/<slug>/      install prefix
```

`<slug>` is `<platform>-usd<version>`, plus `-src` when OpenUSD was built here, so a build
against an existing 25.11 and a from-source 25.11 never share a tree.

Nothing under `build/`, `install_dir/` or the environment is meant to be edited by hand.

## How the dependency set is decided

Per dependency, in this order:

1. **OpenUSD carries it** (it ships a CMake package for it) → link OpenUSD's copy. These are the
   ABI-coupled libraries; two copies in one process is the failure mode this rule exists to
   prevent.
2. **pixi packages it** → install it, pinned to the `VERSIONS.md` version (from scratch) or to the
   version OpenUSD recorded (existing build). A fully qualified version is pinned exactly.
3. **pixi does not package it** → build it once into `build/<slug>/deps` from the source in
   `VERSIONS.md`. Qt Advanced Docking System, sentry-native, OpenMesh and libigl are here
   because conda-forge has no `osx-arm64` build of the first three.
4. **Nothing declares a version** → the plan stops and names the dependency.

`pixi run plan` prints the resulting table (`dependency`, `provider`, `version`, `origin`) and a
verification table comparing the pins with what pixi installed.

## Running an install

The installed binaries run on their own:

```sh
install_dir/osx-arm64-usd25.11-src/bin/dcc_base
```

Three things make that work, and none of them needs a wrapper script:

- **rpath**: the executables and libraries carry `@loader_path/../lib` (and `../plugin/usd`), so
  they find `libopendcc_*` and the Hydra delegates next to themselves.
- **install carries what the process loads at runtime**: `DCC_INSTALL_USD=ON` copies OpenUSD's
  libraries, its `lib/usd` plugin metadata, `lib/python/pxr` and `plugin/usd`;
  `DCC_INSTALL_QT_PLUGINS=ON` copies Qt's plugin directory to `lib/qt6/plugins`. USD and Qt read
  their plugin search path once per process, from the environment, at library-initialization
  time -- before `main()` -- so `Application` registers `lib/usd`/`plugin/usd` with `PlugRegistry`
  and sets `QT_PLUGIN_PATH` from `QLibraryInfo` when the variable is not already set.
- **python path**: the embedded interpreter prepends `<install>/lib/python` and
  `<install>/lib/python<major>.<minor>/site-packages`, so `pxr` and `opendcc` import without
  `PYTHONPATH`.
- **package libraries**: a package is dlopen'ed on its own, so dyld resolves its `@rpath`
  references against that library's own `LC_RPATH`. Each package library therefore carries the
  relative paths to `lib`, `plugin/usd` and the package directories of the targets it links
  (`opendcc_finalize_package_rpaths`).
- **OCIO**: the ACES CG config from `VERSIONS.md` is installed as `ocio/config.ocio`, the file
  color management loads when `$OCIO` is unset. Without it OpenColorIO falls back to its legacy
  built-in config, which has no display view.

`opendcc-env.sh` is still generated (and `DCC_INSTALL_*` off still produces a tree that needs it),
but it is no longer required: it exists for running a build tree's install alongside other tools
and for the case where the libraries are not all inside the prefix.

Python is the build environment's interpreter: `DCC_EMBEDDED_PYTHON_HOME` is `OFF`, so the
application does not point `PYTHONHOME` at an install prefix that has no standard library in it.
A redistributable build sets `DCC_EMBEDDED_PYTHON_HOME=ON` together with `DCC_INSTALL_PYTHON`,
which installs the standard library.

## Tests

`pixi run test` runs 31 CTest tests. Every test runs through `tests/launch_test.py`, which gives
it a throwaway user profile and adds the runtime library paths, the USD python path and the USD
plugin paths.

On macOS arm64 with OpenUSD 25.11, 28 of 31 pass. The three failures are in OpenDCC itself, not
in the environment, and reproduce on any build of this commit:

| Test | Failure |
| ---- | ------- |
| `FileSystemGlobTests` | the glob implementation does not expand POSIX character classes (`[[:digit:]]`) and treats a trailing slash differently from the path it returns |
| `CommandPythonBridgeTests` | `CommandResult::get_result<py::object>()` is empty for a command registered from Python |
| `PackagingWithoutUsdTests` | importing the `opendcc.packaging` extension into a plain interpreter (no `dcc_base`) segfaults in `take_gil` |

## Notes and troubleshooting

- **TBB is 2022.3 because the GPU OpenSubdiv build needs it.** OpenUSD's `hdSt` links
  `OpenSubdiv::osdGPU` whenever GPU support is on, so the plan installs `opensubdiv-gpu`
  (`VERSIONS.md`); that package is built against oneTBB 2022.3. OpenUSD 25.08 and later pick
  their oneTBB code path with `__has_include(<tbb/tbb_stddef.h>)`, so no patch is involved.
- **OpenDCC's own `find_package(Embree 3)`** wants `embree3/rtcore.h`, so Embree 3.13 comes from
  pixi even when OpenUSD's `hdEmbree` plugin uses Embree 4 from its own prefix.
- **Viewport image tests** import `OpenImageIO` from Python. That module is not part of an
  OpenUSD installation, so those tests fail in a clean environment; the build itself is
  unaffected. `pixi run test -- --ctest-arg -E --ctest-arg viewport` skips them.
- **`ctest` after `all`** is reported as a warning, not a build failure: a failing test does not
  invalidate the install.
- **Windows shells**: run the tasks from a normal shell, not from a *Developer Command Prompt*.
  The build imports the Visual Studio environment itself via `vswhere`/`VsDevCmd.bat` when
  `cl.exe` is not already on `PATH`.
- **CMake 4** rejects the `cmake_minimum_required` of some old third-party sources; the OpenMesh
  build passes `CMAKE_POLICY_VERSION_MINIMUM=3.5` for that reason.
- **GL debug annotations** (`glPushDebugGroup`) are OpenGL 4.3 entry points; macOS stops at 4.1
  and the API loader leaves them null, so `GLScopedDebugGroup` makes them a no-op when absent.
- **graphviz package**: conda-forge keeps the plugin libraries in `lib/graphviz`, one level
  below the rest, and their `LC_RPATH` is `@loader_path/..` — correct only in that directory, so
  the package keeps the distribution's layout and `package.unix.toml` names them there. Do not
  move a signed dylib out of its directory: `install_name_tool` invalidates the ad-hoc signature
  and dyld kills the process with `SIGKILL (Code Signature Invalid)`.
- **Reconfiguring from scratch**: `pixi run clean` (or delete `build/<slug>`). Deleting only
  `build/<slug>/cmake` keeps the environment and the source-built dependencies.

## Platform status

Verified on macOS arm64 (OpenUSD built from source and linked from an existing build). The Linux
and Windows paths are implemented — compilers, packages and the MSVC environment import — but
have not been run on a machine yet; see the status table in `VERSIONS.md`.
