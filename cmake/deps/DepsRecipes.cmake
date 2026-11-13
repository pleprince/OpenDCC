# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# Recipes: how each source-built dependency is extracted, patched, configured and installed. No version number
# appears here; everything that can vary comes from the spec (DEPS_DECL_*) and the dependency's features map.
# A recipe is: static data in DEPS_RECIPE_<KEY>_KIND|MARKERS|PATCHES plus one branch in
# opendcc_deps_recipe_plan() that states the requires list, the CMake arguments, the environment and the steps.

# Files that prove the dependency is installed, relative to the prefix; any one existing is enough.
set(DEPS_RECIPE_EMBREE_KIND source)
set(DEPS_RECIPE_EMBREE_MARKERS "lib/cmake/embree-*" "lib/libembree3*" "lib/libembree*.dylib")
# Two dead friend operators print members QuadraticBezierCurve/PointMi no longer have; current clang rejects the
# non-dependent lookup that older clang deferred.
set(DEPS_RECIPE_EMBREE_PATCHES "embree-3.13.5-apple-clang.patch")

set(DEPS_RECIPE_BULLET_KIND source)
set(DEPS_RECIPE_BULLET_MARKERS "lib/libBulletRobotics.a" "lib/libBulletCollision.a")
set(DEPS_RECIPE_BULLET_PATCHES "")

# Installs lib/cmake/qtadvanceddocking-qt6 exporting ads::qtadvanceddocking-qt6.
set(DEPS_RECIPE_QTADS_KIND source)
set(DEPS_RECIPE_QTADS_MARKERS "lib/cmake/qtadvanceddocking-qt6/*.cmake")
# Upstream links Qt6::GuiPrivate on every Qt6 platform, but only linux/ sources need it.
set(DEPS_RECIPE_QTADS_PATCHES "qtads-4.4.1-qt-private.patch")

# MaterialX has no Homebrew formula, and USD's MaterialX support links its shared libraries directly.
set(DEPS_RECIPE_MATERIALX_KIND source)
set(DEPS_RECIPE_MATERIALX_MARKERS "lib/cmake/MaterialX/MaterialXConfig.cmake")
# Storm's Metal generator includes the shared shader library and then emits the node implementations that live in
# that same library as function blocks, so the text lands twice and Metal rejects the program with "class member
# cannot be redeclared". The patch skips a block already emitted verbatim.
set(DEPS_RECIPE_MATERIALX_PATCHES "materialx-1.39.3-include-dedupe.patch")

# Header-only: nothing is built, the tree is only checked and exported as IGL_ROOT.
set(DEPS_RECIPE_LIBIGL_KIND headers)
set(DEPS_RECIPE_LIBIGL_MARKERS "src/libigl/include/igl/igl_inline.h")
set(DEPS_RECIPE_LIBIGL_PATCHES "")

set(DEPS_RECIPE_USD_KIND source)
set(DEPS_RECIPE_USD_MARKERS "lib/cmake/pxr/pxrConfig.cmake" "lib/python/pxr/__init__.py")
# oneTBB 2023 moved the version macros behind a header blocked_range.h no longer pulls in, and dropped the header
# hdEmbree still includes for them.
set(DEPS_RECIPE_USD_PATCHES "usd-25.08-onetbb-version.patch" "usd-25.08-hdembree-onetbb.patch")

set(DEPS_RECIPE_PYSIDE_KIND source)
set(DEPS_RECIPE_PYSIDE_MARKERS "venv/lib/python*/site-packages/PySide6/typesystems/typesystem_core.xml"
                               "venv/bin/shiboken6")
# shiboken parses with Homebrew libclang, which needs the SDK sysroot spelled out on macOS.
set(DEPS_RECIPE_PYSIDE_PATCHES "pyside-6.12.0-macos-sysroot.patch"
                               "pyside-6.12.0-module-symbol-visibility.patch")

# usd.features.<feature> -> CMake switch. Verified against OpenUSD v25.08 cmake/defaults/Options.cmake. Two
# switches older docs list are gone in 25.08: PXR_USE_PYTHON_3 (Python 3 is the only interpreter now) and
# PXR_BUILD_OPENVDB_PLUGIN (folded into PXR_ENABLE_OPENVDB_SUPPORT).
set(DEPS_USD_FEATURE_SWITCHES
    "imaging=PXR_BUILD_IMAGING"
    "usd_imaging=PXR_BUILD_USD_IMAGING"
    "usd_tools=PXR_BUILD_USD_TOOLS"
    "usdview=PXR_BUILD_USDVIEW"
    "python=PXR_ENABLE_PYTHON_SUPPORT"
    "gl=PXR_ENABLE_GL_SUPPORT"
    "metal=PXR_ENABLE_METAL_SUPPORT"
    "openimageio=PXR_BUILD_OPENIMAGEIO_PLUGIN"
    "opencolorio=PXR_BUILD_OPENCOLORIO_PLUGIN"
    "hdf5=PXR_ENABLE_HDF5_SUPPORT"
    "ptex=PXR_ENABLE_PTEX_SUPPORT"
    "alembic=PXR_BUILD_ALEMBIC_PLUGIN"
    "openvdb=PXR_ENABLE_OPENVDB_SUPPORT"
    "embree=PXR_BUILD_EMBREE_PLUGIN"
    "prman=PXR_BUILD_PRMAN_PLUGIN"
    "materialx=PXR_ENABLE_MATERIALX_SUPPORT"
    "draco=PXR_BUILD_DRACO_PLUGIN"
    "osl=PXR_ENABLE_OSL_SUPPORT"
    "tests=PXR_BUILD_TESTS"
    "examples=PXR_BUILD_EXAMPLES"
    "tutorials=PXR_BUILD_TUTORIALS")

# usd.features.<feature> needs the matching dependency keg on CMAKE_PREFIX_PATH.
set(DEPS_USD_FEATURE_KEGS
    "openimageio=openimageio"
    "opencolorio=opencolorio"
    "hdf5=hdf5"
    "ptex=ptex"
    "alembic=alembic"
    "openvdb=openvdb"
    "embree=embree"
    "materialx=materialx"
    "draco=draco"
    "osl=osl")

# Directory to build against: that dependency's Homebrew keg, or our own prefix for source builds. Memoized in a
# global property because `brew --prefix` is a process spawn and the generated cache asks for every keg.
function(opendcc_deps_keg out name)
    opendcc_deps_key(_key "${name}")
    get_property(_cached GLOBAL PROPERTY "DEPS_KEG_${_key}")
    if(NOT "${_cached}" STREQUAL "")
        set(${out} "${_cached}" PARENT_SCOPE)
        return()
    endif()
    opendcc_deps_decl(_provider "${name}" PROVIDER)
    if("${_provider}" STREQUAL "brew")
        opendcc_deps_decl(_formula "${name}" FORMULA)
        opendcc_deps_brew_prefix(_path "${_formula}")
        if("${_path}" STREQUAL "")
            opendcc_deps_die("brew formula \"${_formula}\" for dependency \"${name}\" is not installed; run "
                             "cmake --preset ${DEPS_PLATFORM_TAG}-deps first")
        endif()
        set_property(GLOBAL PROPERTY "DEPS_KEG_${_key}" "${_path}")
        set(${out} "${_path}" PARENT_SCOPE)
        return()
    endif()
    if("${_provider}" STREQUAL "source" OR "${_provider}" STREQUAL "headers")
        set_property(GLOBAL PROPERTY "DEPS_KEG_${_key}" "${DEPS_PREFIX}")
        set(${out} "${DEPS_PREFIX}" PARENT_SCOPE)
        return()
    endif()
    opendcc_deps_die("dependency \"${name}\" uses provider \"${_provider}\" and its location cannot be derived")
endfunction()

function(opendcc_deps_qt_major out)
    string(REGEX MATCH "^[0-9]+" _major "${DEPS_SPEC_QT_VERSION}")
    set(${out} "${_major}" PARENT_SCOPE)
endfunction()

# The Qt prefix whose lib/cmake can resolve every module, private packages included: Homebrew splits Qt into kegs
# and Qt resolves a component relative to the prefix its Qt6Config.cmake lives under, so pointing at the qtbase keg
# alone makes e.g. Qt6QmlPrivate unfindable. The Homebrew prefix links every module's config directory into one
# lib/cmake.
function(opendcc_deps_qt_install_prefix out)
    opendcc_deps_keg(_keg qtbase)
    get_filename_component(_candidate "${_keg}" DIRECTORY)
    get_filename_component(_candidate "${_candidate}" DIRECTORY)
    opendcc_deps_qt_major(_major)
    if(EXISTS "${_candidate}/lib/cmake/Qt${_major}/Qt${_major}Config.cmake")
        set(${out} "${_candidate}" PARENT_SCOPE)
    else()
        set(${out} "${_keg}" PARENT_SCOPE)
    endif()
endfunction()

# Arguments every source recipe gets: release, our prefix, the architecture, the policy floor and the kegs it
# builds against.
function(opendcc_deps_common_cmake_args out requires_var)
    set(_args "-DCMAKE_BUILD_TYPE=Release")
    opendcc_deps_list_append(_args "-DCMAKE_INSTALL_PREFIX=${DEPS_PREFIX}")
    opendcc_deps_platform_cmake_args(_platform_args)
    foreach(_argument IN LISTS _platform_args)
        opendcc_deps_list_append(_args "${_argument}")
    endforeach()
    # CMake 4 rejects cmake_minimum_required(<3.5), which every old dependency here still declares.
    opendcc_deps_list_append(_args "-DCMAKE_POLICY_VERSION_MINIMUM=3.5")
    set(_prefix_path "${DEPS_PREFIX}")
    foreach(_required IN LISTS ${requires_var})
        if("${_required}" STREQUAL "python")
            continue()
        endif()
        opendcc_deps_keg(_keg "${_required}")
        opendcc_deps_list_append(_prefix_path "${_keg}")
    endforeach()
    string(JOIN ";" _prefix_path_text ${_prefix_path})
    opendcc_deps_list_append(_args "-DCMAKE_PREFIX_PATH=${_prefix_path_text}")
    set(${out} "${_args}" PARENT_SCOPE)
endfunction()

function(opendcc_deps_recipe_kind out name)
    opendcc_deps_key(_key "${name}")
    set(${out} "${DEPS_RECIPE_${_key}_KIND}" PARENT_SCOPE)
endfunction()

function(opendcc_deps_recipe_present out name)
    opendcc_deps_key(_key "${name}")
    set(_found OFF)
    foreach(_marker IN LISTS DEPS_RECIPE_${_key}_MARKERS)
        file(GLOB _matches "${DEPS_PREFIX}/${_marker}")
        if(_matches)
            set(_found ON)
            break()
        endif()
    endforeach()
    set(${out} ${_found} PARENT_SCOPE)
endfunction()

# opendcc_deps_recipe_plan(<name> <out-json> <out-steps> <out-env> <out-requires>): the canonical description of
# what building <name> means. The JSON is hashed into the stamp; the steps and environment are what the driver
# runs. A dependency only ever records a plan here; it must exist for every enabled source/headers dependency.
function(opendcc_deps_recipe_plan name out_json out_steps out_env out_requires)
    opendcc_deps_key(_key "${name}")
    if(NOT DEFINED DEPS_RECIPE_${_key}_KIND)
        opendcc_deps_decl(_provider "${name}" PROVIDER)
        opendcc_deps_die("enabled ${_provider} dependency \"${name}\" has no recipe in "
                         "cmake/deps/DepsRecipes.cmake")
    endif()
    set(_kind "${DEPS_RECIPE_${_key}_KIND}")
    set(_markers "${DEPS_RECIPE_${_key}_MARKERS}")
    set(_patches "${DEPS_RECIPE_${_key}_PATCHES}")
    set(_src "${DEPS_PREFIX}/src/${name}")
    set(_build "${DEPS_PREFIX}/build/${name}")

    set(_requires "")
    set(_cmake_args "")
    set(_env "")
    set(_steps "")
    set(_extra_steps "")
    set(_default_steps ON)

    if("${name}" STREQUAL "embree")
        set(_cmake_args
            "-DEMBREE_ISPC_SUPPORT=OFF"
            "-DEMBREE_TUTORIALS=OFF"
            "-DEMBREE_TASKING_SYSTEM=INTERNAL"
            "-DBUILD_SHARED_LIBS=ON")
    elseif("${name}" STREQUAL "bullet")
        # FindBullet3.cmake needs BulletRobotics plus the static libs directly in <root>/lib.
        set(_cmake_args
            "-DBUILD_SHARED_LIBS=OFF"
            "-DBUILD_BULLET_ROBOTICS=ON"
            "-DBUILD_BULLET2_DEMOS=OFF"
            "-DBUILD_OPENGL3_DEMOS=OFF"
            "-DBUILD_CPU_DEMOS=OFF"
            "-DBUILD_UNIT_TESTS=OFF"
            "-DINSTALL_LIBS=ON")
        # VHACD is compiled into BulletRobotics, but bullet has no install rule for its public header, which
        # opendcc.usd_editor.bullet_physics includes as <VHACD.h>.
        set(_step_arguments "${CMAKE_COMMAND}" -E make_directory "${DEPS_PREFIX}/include")
        opendcc_deps_pack_step(_step make-include-dir _step_arguments)
        opendcc_deps_list_append(_extra_steps "${_step}")
        set(_step_arguments "${CMAKE_COMMAND}" -E copy_if_different "${_src}/Extras/VHACD/public/VHACD.h"
                            "${DEPS_PREFIX}/include/VHACD.h")
        opendcc_deps_pack_step(_step install-vhacd-header _step_arguments)
        opendcc_deps_list_append(_extra_steps "${_step}")
    elseif("${name}" STREQUAL "qtads")
        opendcc_deps_decl(_version "${name}" VERSION)
        # The tarball has no git index, which upstream falls back to for its version; ADS_VERSION skips that.
        set(_cmake_args
            "-DADS_VERSION=${_version}"
            "-DBUILD_EXAMPLES=OFF"
            "-DBUILD_STATIC=OFF"
            "-DCMAKE_INSTALL_LIBDIR=lib")
        opendcc_deps_list_append(_requires qtbase)
    elseif("${name}" STREQUAL "materialx")
        # Shared, because hdSt and usdMtlx link it; the generators USD does not call are off to keep the build
        # small, and every optional dependency (Python, OIIO, OCIO, viewer) is off so nothing else is pulled in.
        set(_cmake_args
            "-DMATERIALX_BUILD_SHARED_LIBS=ON"
            "-DMATERIALX_BUILD_MONOLITHIC=ON"
            "-DMATERIALX_BUILD_PYTHON=OFF"
            "-DMATERIALX_INSTALL_PYTHON=OFF"
            "-DMATERIALX_BUILD_VIEWER=OFF"
            "-DMATERIALX_BUILD_GRAPH_EDITOR=OFF"
            "-DMATERIALX_BUILD_TESTS=OFF"
            "-DMATERIALX_BUILD_OIIO=OFF"
            "-DMATERIALX_BUILD_OCIO=OFF"
            "-DMATERIALX_BUILD_OSOS=OFF")
    elseif("${name}" STREQUAL "libigl")
        # Header-only: the archive is extracted and checked, nothing is configured or built.
        set(_default_steps OFF)
    elseif("${name}" STREQUAL "usd")
        # Every dependency USD links against has to come from the pinned kegs: with only some of them on
        # CMAKE_PREFIX_PATH, USD's configure falls through to whatever install the machine happens to expose (here
        # a pre-existing OpenSubdiv 3.6.1), bakes that @rpath into its libraries and the render delegate then fails
        # to load at runtime.
        set(_requires python boost tbb opensubdiv imath openexr)
        foreach(_entry IN LISTS DEPS_USD_FEATURE_KEGS)
            string(FIND "${_entry}" "=" _split)
            string(SUBSTRING "${_entry}" 0 ${_split} _feature)
            math(EXPR _value_start "${_split}+1")
            string(SUBSTRING "${_entry}" ${_value_start} -1 _dependency)
            opendcc_deps_dep_feature(_on usd "${_feature}")
            if(_on)
                opendcc_deps_list_append(_requires "${_dependency}")
            endif()
        endforeach()
        opendcc_deps_dep_feature(_openimageio_on usd openimageio)
        if(_openimageio_on)
            # OpenImageIO's headers include <fmt/format.h>; the keg has to be on the include path.
            opendcc_deps_list_append(_requires fmt)
        endif()
        opendcc_deps_platform_venv_python(_python_exe "${DEPS_PREFIX}")
        opendcc_deps_keg(_tbb_keg tbb)
        set(_cmake_args "-DPython3_EXECUTABLE=${_python_exe}" "-DTBB_ROOT=${_tbb_keg}")
        if(_openimageio_on)
            opendcc_deps_keg(_fmt_keg fmt)
            opendcc_deps_list_append(_cmake_args "-DCMAKE_CXX_FLAGS=-isystem ${_fmt_keg}/include")
        endif()
        # Every switch is emitted explicitly, ON or OFF, so a cached build tree cannot keep an old feature set.
        foreach(_entry IN LISTS DEPS_USD_FEATURE_SWITCHES)
            string(FIND "${_entry}" "=" _split)
            string(SUBSTRING "${_entry}" 0 ${_split} _feature)
            math(EXPR _value_start "${_split}+1")
            string(SUBSTRING "${_entry}" ${_value_start} -1 _switch)
            opendcc_deps_dep_feature(_on usd "${_feature}")
            if(_on)
                set(_value "ON")
            else()
                set(_value "OFF")
            endif()
            opendcc_deps_list_append(_cmake_args "-D${_switch}=${_value}")
        endforeach()
    elseif("${name}" STREQUAL "pyside")
        # Built with its own distutils front end: Homebrew's bottle targets a newer interpreter than the spec's.
        # setup.py install is the documented flow and installs PySide6, shiboken6 and their typesystems into the
        # venv, which is exactly what find_package(PySide6) and the typesystem substitutions need.
        set(_default_steps OFF)
        set(_requires qtbase qtshadertools qtdeclarative qtquick3d python llvm)
        set(_qt_kegs "")
        foreach(_required IN LISTS _requires)
            if("${_required}" MATCHES "^qt")
                opendcc_deps_keg(_keg "${_required}")
                opendcc_deps_list_append(_qt_kegs "${_keg}")
            endif()
        endforeach()
        string(JOIN ";" _qt_prefix_path ${_qt_kegs})
        # setup.py needs qtpaths6 on PATH, libclang via LLVM_INSTALL_DIR and every Qt module keg on
        # CMAKE_PREFIX_PATH: a sibling module's private package (Qt6QmlPrivate for the Qml bindings) is only found
        # through the prefix path.
        opendcc_deps_keg(_llvm_keg llvm)
        opendcc_deps_keg(_qtbase_keg qtbase)
        opendcc_deps_qt_install_prefix(_qt_prefix)
        set(_path_dirs "")
        opendcc_deps_list_append(_path_dirs "${_llvm_keg}/bin")
        opendcc_deps_list_append(_path_dirs "${_qtbase_keg}/bin")
        opendcc_deps_list_append(_path_dirs "${_qt_prefix}/bin")
        string(JOIN ":" _path_text ${_path_dirs})
        opendcc_deps_list_append(_env "LLVM_INSTALL_DIR=${_llvm_keg}")
        opendcc_deps_list_append(_env "CMAKE_PREFIX_PATH=${_qt_prefix_path}")
        # Only the directories this recipe prepends: the inherited PATH is added when the step runs, so the plan (and
        # therefore the stamp) does not change when the shell's PATH does.
        opendcc_deps_list_append(_env "PATH=${_path_text}")
        opendcc_deps_platform_sdkroot(_sdkroot)
        if(NOT "${_sdkroot}" STREQUAL "")
            # shiboken parses with libclang from Homebrew, which does not know the SDK sysroot the way Apple's
            # clang does; without it the bundled libc++ headers fail on missing <math.h> macros.
            opendcc_deps_list_append(_env "SDKROOT=${_sdkroot}")
        endif()
        opendcc_deps_platform_venv_python(_python_exe "${DEPS_PREFIX}")
        set(_step_arguments
            "${_python_exe}"
            "${_src}/setup.py"
            install
            "--qt-target-path=${_qt_prefix}"
            "--limited-api=no"
            "--no-qt-tools"
            "--parallel=${DEPS_JOBS}"
            "--cmake=${CMAKE_COMMAND}")
        opendcc_deps_pack_step(_step install _step_arguments)
        opendcc_deps_list_append(_steps "${_step}")
    endif()

    if(_default_steps)
        opendcc_deps_common_cmake_args(_common_args _requires)
        set(_step_arguments "${CMAKE_COMMAND}" -S "${_src}" -B "${_build}" -G Ninja)
        foreach(_argument IN LISTS _common_args)
            opendcc_deps_list_append(_step_arguments "${_argument}")
        endforeach()
        foreach(_argument IN LISTS _cmake_args)
            opendcc_deps_list_append(_step_arguments "${_argument}")
        endforeach()
        opendcc_deps_pack_step(_step configure _step_arguments)
        opendcc_deps_list_append(_steps "${_step}")
        set(_step_arguments "${CMAKE_COMMAND}" --build "${_build}" -j "${DEPS_JOBS}")
        opendcc_deps_pack_step(_step build _step_arguments)
        opendcc_deps_list_append(_steps "${_step}")
        set(_step_arguments "${CMAKE_COMMAND}" --install "${_build}")
        opendcc_deps_pack_step(_step install _step_arguments)
        opendcc_deps_list_append(_steps "${_step}")
    endif()
    foreach(_step IN LISTS _extra_steps)
        opendcc_deps_list_append(_steps "${_step}")
    endforeach()

    opendcc_deps_patch_digests(_patch_digests "${_patches}")
    opendcc_deps_plan_json(_json _kind _markers _patches _patch_digests _requires _steps _env)
    set(${out_json} "${_json}" PARENT_SCOPE)
    set(${out_steps} "${_steps}" PARENT_SCOPE)
    set(${out_env} "${_env}" PARENT_SCOPE)
    set(${out_requires} "${_requires}" PARENT_SCOPE)
endfunction()

# Hash of everything that decides what gets built: the plan (kind, patches and their digests, requires, the
# normalized steps, the environment) plus version, url and the features map.
function(opendcc_deps_recipe_digest_from_plan out name plan)
    opendcc_deps_decl(_version "${name}" VERSION)
    opendcc_deps_decl(_url "${name}" URL)
    opendcc_deps_decl(_features "${name}" FEATURES)
    opendcc_deps_sha256_text(_digest "${plan}|${_version}|${_url}|${_features}")
    set(${out} "${_digest}" PARENT_SCOPE)
endfunction()

function(opendcc_deps_recipe_digest out name)
    opendcc_deps_recipe_plan("${name}" _plan _steps _env _requires)
    opendcc_deps_recipe_digest_from_plan(_digest "${name}" "${_plan}")
    set(${out} "${_digest}" PARENT_SCOPE)
endfunction()

# True when every dependency <name> builds against and that has a recipe is either installed or already scheduled.
function(opendcc_deps_recipe_ready out name scheduled_var)
    opendcc_deps_recipe_plan("${name}" _plan _steps _env _requires)
    set(_ready ON)
    foreach(_required IN LISTS _requires)
        opendcc_deps_key(_required_key "${_required}")
        if(NOT DEFINED DEPS_RECIPE_${_required_key}_KIND)
            continue()
        endif()
        opendcc_deps_recipe_present(_present "${_required}")
        if(_present)
            continue()
        endif()
        if(NOT "${_required}" IN_LIST ${scheduled_var})
            set(_ready OFF)
        endif()
    endforeach()
    set(${out} ${_ready} PARENT_SCOPE)
endfunction()

# Provisioning order for source targets: dependency order, not spec order. A fresh prefix has to complete in one
# run, and usd (for instance) builds against materialx, which the spec lists after it. Ties and cycles keep the
# incoming order, and a cycle is not an error here — provision_source reports the missing dependency itself.
function(opendcc_deps_order_targets out targets_var)
    set(_pending "${${targets_var}}")
    set(_ordered "")
    while(NOT _pending STREQUAL "")
        set(_emitted OFF)
        set(_index 0)
        foreach(_name IN LISTS _pending)
            opendcc_deps_recipe_ready(_ready "${_name}" _ordered)
            if(_ready)
                opendcc_deps_list_append(_ordered "${_name}")
                list(REMOVE_AT _pending ${_index})
                set(_emitted ON)
                break()
            endif()
            math(EXPR _index "${_index}+1")
        endforeach()
        if(NOT _emitted)
            foreach(_name IN LISTS _pending)
                opendcc_deps_list_append(_ordered "${_name}")
            endforeach()
            break()
        endif()
    endwhile()
    set(${out} "${_ordered}" PARENT_SCOPE)
endfunction()

# Checks on the extracted tree, before any step runs. libigl is only ever extracted, so its presence is what has
# to be proven.
function(opendcc_deps_recipe_verify_libigl src)
    if(NOT EXISTS "${src}/include/igl/igl_inline.h")
        opendcc_deps_die("include/igl/igl_inline.h is missing from the libigl archive")
    endif()
endfunction()
