# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# Dependency spec: the static tables that constrain it, the functions a spec file calls, and the validation the
# driver runs before touching the prefix. A spec (deps/<platform>.cmake) is data: it only calls the
# opendcc_deps_spec_* functions below, which store one variable per field in this directory's scope:
#
#   DEPS_SPEC_SCHEMA, DEPS_SPEC_PLATFORM                       top-level begin()
#   DEPS_SPEC_PYTHON_VERSION|PROVIDER|FORMULA                  top-level python block
#   DEPS_SPEC_QT_VERSION|QT_PYSIDE                             top-level qt block
#   DEPS_SPEC_OCIO_DECLARED|OCIO_CONFIG_VERSION|OCIO_URL|OCIO_SHA256
#   DEPS_SPEC_OPENDCC_<KEY>                                    one per opendcc key
#   DEPS_DECL_<KEY>_DECLARED|ENABLED|PROVIDER|FORMULA|VERSION|EXPECT|URL|SHA256|STRIP|PREFIX|CMAKE_VARS|FEATURES
#
# <KEY> is the dependency name upper-cased with '-' replaced by '_' (opendcc_deps_key). CMAKE_VARS and FEATURES
# are lists of VAR=VALUE / feature=ON|OFF entries, merged per key so an overlay may restate a single entry.

# Dependency order is the provisioning order; recipes may not rely on it (dependencies are resolved from their
# requires list), but reports read better when the foundation comes first.
set(DEPS_KNOWN_DEPENDENCIES
    python
    boost
    eigen
    tbb
    glew
    zmq
    graphviz
    doctest
    openmesh
    opensubdiv
    openimageio
    fmt
    opencolorio
    imath
    openexr
    sentry
    llvm
    qtbase
    qtmultimedia
    qtsvg
    qttools
    qtshadertools
    qtdeclarative
    qtquick3d
    pybind11
    embree
    bullet
    qtads
    libigl
    usd
    pyside
    alembic
    openvdb
    ptex
    hdf5
    partio
    draco
    materialx
    skia
    opentimelineio
    arnold
    cycles
    osl)

# USD build switches, in the order they are emitted into the generated cache.
set(DEPS_USD_FEATURES
    imaging
    usd_imaging
    usd_tools
    usdview
    python
    gl
    metal
    openimageio
    fmt
    opencolorio
    hdf5
    ptex
    alembic
    openvdb
    embree
    prman
    materialx
    draco
    osl
    tests
    examples
    tutorials)

# `external` means "already installed elsewhere": the spec names its PREFIX and the driver verifies it instead of
# building anything.
set(DEPS_PROVIDERS brew source headers manual external)

# spec key -> generated CMake option (1:1, no other mapping).
set(DEPS_OPENDCC_KEYS
    "tests=DCC_BUILD_TESTS"
    "i18n=DCC_BUILD_I18N"
    "crash_reporter=DCC_BUILD_CRASH_REPORTER"
    "render_view=DCC_BUILD_RENDER_VIEW"
    "node_editor=DCC_NODE_EDITOR"
    "bullet_physics=DCC_BUILD_BULLET_PHYSICS"
    "arnold_support=DCC_BUILD_ARNOLD_SUPPORT"
    "cycles_support=DCC_BUILD_CYCLES_SUPPORT"
    "renderman_support=DCC_BUILD_RENDERMAN_SUPPORT"
    "use_ptex=DCC_USE_PTEX"
    "use_houdini=DCC_HOUDINI_SUPPORT"
    "use_katana=DCC_KATANA_SUPPORT")

# Dependency-level edges. A disabled dependency listed here may not be required by an enabled one. Homebrew ships
# each Qt module as its own keg, so a module whose CMake config references another module's private package
# (QtMultimedia -> Qml) only resolves when that keg is present.
set(DEPS_DEP_REQUIRES
    "qttools=qtbase"
    "qtmultimedia=qtbase,qtdeclarative,qtquick3d"
    "qtsvg=qtbase"
    "qtshadertools=qtbase"
    "pyside=qtbase,qtshadertools,qtdeclarative,qtquick3d,python,llvm"
    "usd=python"
    "qtdeclarative=qtbase"
    "qtquick3d=qtbase,qtdeclarative"
    "openimageio=fmt")

# usd.features.<feature> needs the matching dependency.
set(DEPS_USD_FEATURE_DEPS
    "alembic=alembic"
    "openvdb=openvdb"
    "ptex=ptex"
    "embree=embree"
    "materialx=materialx"
    "draco=draco"
    "hdf5=hdf5"
    "openimageio=openimageio"
    "opencolorio=opencolorio")

# usd.features.<feature> implies another usd feature.
set(DEPS_USD_FEATURE_IMPLIES "usd_imaging=imaging" "usdview=imaging")

# Features with no macOS arm64 build at all; enabling them is an error, not a missing dependency.
set(DEPS_USD_UNSUPPORTED "prman=has no macOS arm64 build")

# opendcc.<key> needs the matching dependency.
set(DEPS_OPENDCC_REQUIRES
    "tests=doctest"
    "crash_reporter=sentry"
    "render_view=qtmultimedia"
    "node_editor=graphviz"
    "bullet_physics=bullet"
    "use_ptex=ptex"
    "arnold_support=arnold"
    "cycles_support=cycles,osl")

# Fixed by the provisioned-prefix model; a preset or -D value still wins.
set(DEPS_CMAKE_BOOL_DEFAULTS "DCC_USE_PYTHON_3" "DCC_PYSIDE_CMAKE_FIND" "DCC_INSTALL_USD" "DCC_INSTALL_PYSIDE2"
                             "DCC_INSTALL_PYTHON")

# Kept off CMAKE_PREFIX_PATH: llvm would let CMake pick Homebrew's clang, python is addressed through the venv.
set(DEPS_PREFIX_PATH_EXCLUDE python llvm)

function(opendcc_deps_spec_reset)
    set(DEPS_SPEC_SCHEMA ""
        PARENT_SCOPE)
    set(DEPS_SPEC_PLATFORM ""
        PARENT_SCOPE)
    set(DEPS_SPEC_PYTHON_VERSION ""
        PARENT_SCOPE)
    set(DEPS_SPEC_PYTHON_PROVIDER ""
        PARENT_SCOPE)
    set(DEPS_SPEC_PYTHON_FORMULA ""
        PARENT_SCOPE)
    set(DEPS_SPEC_QT_VERSION ""
        PARENT_SCOPE)
    set(DEPS_SPEC_QT_PYSIDE ""
        PARENT_SCOPE)
    set(DEPS_SPEC_OCIO_DECLARED OFF
        PARENT_SCOPE)
    set(DEPS_SPEC_OCIO_CONFIG_VERSION ""
        PARENT_SCOPE)
    set(DEPS_SPEC_OCIO_URL ""
        PARENT_SCOPE)
    set(DEPS_SPEC_OCIO_SHA256 ""
        PARENT_SCOPE)
    foreach(_entry IN LISTS DEPS_OPENDCC_KEYS)
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _key)
        string(TOUPPER "${_key}" _key)
        set(DEPS_SPEC_OPENDCC_${_key} OFF
            PARENT_SCOPE)
    endforeach()
    foreach(_name IN LISTS DEPS_KNOWN_DEPENDENCIES)
        opendcc_deps_key(_key "${_name}")
        set(DEPS_DECL_${_key}_DECLARED OFF
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_ENABLED OFF
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_PROVIDER ""
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_FORMULA ""
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_VERSION ""
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_EXPECT ""
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_URL ""
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_SHA256 ""
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_STRIP 1
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_PREFIX ""
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_ALIGN ""
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_CMAKE_VARS ""
            PARENT_SCOPE)
        set(DEPS_DECL_${_key}_FEATURES ""
            PARENT_SCOPE)
    endforeach()
endfunction()

function(opendcc_deps_spec_begin)
    cmake_parse_arguments(PARSE_ARGV 0 arg "" "PLATFORM;SCHEMA" "")
    if(arg_UNPARSED_ARGUMENTS)
        opendcc_deps_die("opendcc_deps_spec_begin: unknown argument \"${arg_UNPARSED_ARGUMENTS}\"; known: PLATFORM, "
                         "SCHEMA")
    endif()
    set(DEPS_SPEC_PLATFORM "${arg_PLATFORM}"
        PARENT_SCOPE)
    set(DEPS_SPEC_SCHEMA "${arg_SCHEMA}"
        PARENT_SCOPE)
endfunction()

function(opendcc_deps_spec_python)
    cmake_parse_arguments(PARSE_ARGV 0 arg "" "VERSION;PROVIDER;FORMULA" "")
    if(arg_UNPARSED_ARGUMENTS)
        opendcc_deps_die("opendcc_deps_spec_python: unknown argument \"${arg_UNPARSED_ARGUMENTS}\"; known: "
                         "VERSION, PROVIDER, FORMULA")
    endif()
    set(DEPS_SPEC_PYTHON_VERSION "${arg_VERSION}"
        PARENT_SCOPE)
    set(DEPS_SPEC_PYTHON_PROVIDER "${arg_PROVIDER}"
        PARENT_SCOPE)
    set(DEPS_SPEC_PYTHON_FORMULA "${arg_FORMULA}"
        PARENT_SCOPE)
endfunction()

function(opendcc_deps_spec_qt)
    cmake_parse_arguments(PARSE_ARGV 0 arg "" "VERSION;PYSIDE" "")
    if(arg_UNPARSED_ARGUMENTS)
        opendcc_deps_die("opendcc_deps_spec_qt: unknown argument \"${arg_UNPARSED_ARGUMENTS}\"; known: VERSION, "
                         "PYSIDE")
    endif()
    set(DEPS_SPEC_QT_VERSION "${arg_VERSION}"
        PARENT_SCOPE)
    set(DEPS_SPEC_QT_PYSIDE "${arg_PYSIDE}"
        PARENT_SCOPE)
endfunction()

function(opendcc_deps_spec_ocio)
    cmake_parse_arguments(PARSE_ARGV 0 arg "" "CONFIG_VERSION;URL;SHA256" "")
    if(arg_UNPARSED_ARGUMENTS)
        opendcc_deps_die("opendcc_deps_spec_ocio: unknown argument \"${arg_UNPARSED_ARGUMENTS}\"; known: "
                         "CONFIG_VERSION, URL, SHA256")
    endif()
    set(DEPS_SPEC_OCIO_DECLARED ON
        PARENT_SCOPE)
    set(DEPS_SPEC_OCIO_CONFIG_VERSION "${arg_CONFIG_VERSION}"
        PARENT_SCOPE)
    set(DEPS_SPEC_OCIO_URL "${arg_URL}"
        PARENT_SCOPE)
    set(DEPS_SPEC_OCIO_SHA256 "${arg_SHA256}"
        PARENT_SCOPE)
endfunction()

# opendcc(TESTS=ON I18N=OFF ...): one KEY=VALUE per spec key.
function(opendcc_deps_spec_opendcc)
    set(_known "")
    foreach(_entry IN LISTS DEPS_OPENDCC_KEYS)
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _key)
        string(TOUPPER "${_key}" _key)
        opendcc_deps_list_append(_known "${_key}")
    endforeach()
    foreach(_pair IN LISTS ARGN)
        string(FIND "${_pair}" "=" _split)
        if(_split LESS 0)
            opendcc_deps_die("opendcc_deps_spec_opendcc: \"${_pair}\" must be <key>=ON|OFF")
        endif()
        string(SUBSTRING "${_pair}" 0 ${_split} _key)
        string(TOUPPER "${_key}" _key)
        math(EXPR _value_start "${_split}+1")
        string(SUBSTRING "${_pair}" ${_value_start} -1 _value)
        if(NOT "${_key}" IN_LIST _known)
            opendcc_deps_die("opendcc_deps_spec_opendcc: unknown key \"${_key}\"; known: ${_known}")
        endif()
        if(NOT "${_value}" STREQUAL "ON" AND NOT "${_value}" STREQUAL "OFF")
            opendcc_deps_die("opendcc_deps_spec_opendcc: ${_key} must be ON or OFF, found \"${_value}\"")
        endif()
        set(DEPS_SPEC_OPENDCC_${_key} ${_value}
            PARENT_SCOPE)
    endforeach()
endfunction()

# Merge VAR=VALUE / feature=ON|OFF entries per key: an entry restated by the caller replaces the stored one.
function(opendcc_deps_merge_kv out existing new)
    set(_new_keys "")
    foreach(_entry IN LISTS new)
        string(FIND "${_entry}" "=" _split)
        if(_split GREATER -1)
            string(SUBSTRING "${_entry}" 0 ${_split} _key)
        else()
            set(_key "${_entry}")
        endif()
        opendcc_deps_list_append(_new_keys "${_key}")
    endforeach()
    set(_result "")
    foreach(_entry IN LISTS existing)
        string(FIND "${_entry}" "=" _split)
        if(_split GREATER -1)
            string(SUBSTRING "${_entry}" 0 ${_split} _key)
        else()
            set(_key "${_entry}")
        endif()
        if(NOT "${_key}" IN_LIST _new_keys)
            opendcc_deps_list_append(_result "${_entry}")
        endif()
    endforeach()
    foreach(_entry IN LISTS new)
        opendcc_deps_list_append(_result "${_entry}")
    endforeach()
    set(${out} "${_result}" PARENT_SCOPE)
endfunction()

# opendcc_deps_spec_dependency(<name> [ENABLED ON|OFF] [PROVIDER brew|source|headers|manual|external]
#     [FORMULA <f>] [VERSION <v>] [EXPECT <range>] [URL <u>] [SHA256 <hash>] [STRIP <n>] [PREFIX <dir>]
#     [ALIGN ON|OFF] [CMAKE_VARS <VAR=VALUE>...] [FEATURES <usd-feature=ON|OFF>...])
#
# Called again for the same dependency (from the overlay) it replaces exactly the fields it states; CMAKE_VARS and
# FEATURES merge per key. PREFIX is only meaningful with PROVIDER external: it is the absolute install prefix the
# dependency was built into. ALIGN (default ON, external only) adopts what that installation reports — its release,
# its dependency pins, its feature set — instead of demanding the spec match; ALIGN OFF verifies the spec against it.
function(opendcc_deps_spec_dependency name)
    cmake_parse_arguments(PARSE_ARGV 1 arg ""
                          "ENABLED;PROVIDER;FORMULA;VERSION;EXPECT;URL;SHA256;STRIP;PREFIX;ALIGN"
                          "CMAKE_VARS;FEATURES")
    if(NOT "${name}" IN_LIST DEPS_KNOWN_DEPENDENCIES)
        opendcc_deps_die("opendcc_deps_spec_dependency: unknown dependency \"${name}\"; known: "
                         "${DEPS_KNOWN_DEPENDENCIES}")
    endif()
    opendcc_deps_key(_key "${name}")
    if(arg_UNPARSED_ARGUMENTS)
        string(REPLACE ";" ", " _unparsed "${arg_UNPARSED_ARGUMENTS}")
        opendcc_deps_die("opendcc_deps_spec_dependency(${name}): unknown argument \"${_unparsed}\"; known: "
                         "ENABLED, PROVIDER, FORMULA, VERSION, EXPECT, URL, SHA256, STRIP, PREFIX, ALIGN, "
                         "CMAKE_VARS, FEATURES")
    endif()
    if(DEFINED arg_ENABLED AND NOT "${arg_ENABLED}" STREQUAL "ON" AND NOT "${arg_ENABLED}" STREQUAL "OFF")
        opendcc_deps_die("opendcc_deps_spec_dependency(${name}): ENABLED must be ON or OFF, found "
                         "\"${arg_ENABLED}\"")
    endif()
    if(DEFINED arg_ALIGN AND NOT "${arg_ALIGN}" STREQUAL "ON" AND NOT "${arg_ALIGN}" STREQUAL "OFF")
        opendcc_deps_die("opendcc_deps_spec_dependency(${name}): ALIGN must be ON or OFF, found \"${arg_ALIGN}\"")
    endif()
    if(DEFINED arg_PROVIDER AND NOT "${arg_PROVIDER}" IN_LIST DEPS_PROVIDERS)
        opendcc_deps_die("opendcc_deps_spec_dependency(${name}): PROVIDER must be one of ${DEPS_PROVIDERS}, found "
                         "\"${arg_PROVIDER}\"")
    endif()
    if(DEFINED arg_CMAKE_VARS)
        foreach(_entry IN LISTS arg_CMAKE_VARS)
            string(FIND "${_entry}" "=" _split)
            if(_split LESS 1)
                opendcc_deps_die("opendcc_deps_spec_dependency(${name}): CMAKE_VARS entry \"${_entry}\" must be "
                                 "<VAR>=<value>")
            endif()
        endforeach()
    endif()
    if(DEFINED arg_FEATURES)
        if(NOT "${name}" STREQUAL "usd")
            opendcc_deps_die("opendcc_deps_spec_dependency(${name}): only usd takes FEATURES")
        endif()
        foreach(_entry IN LISTS arg_FEATURES)
            string(FIND "${_entry}" "=" _split)
            if(_split LESS 1)
                opendcc_deps_die("opendcc_deps_spec_dependency(${name}): FEATURES entry \"${_entry}\" must be "
                                 "<feature>=ON|OFF")
            endif()
            string(SUBSTRING "${_entry}" 0 ${_split} _feature)
            math(EXPR _value_start "${_split}+1")
            string(SUBSTRING "${_entry}" ${_value_start} -1 _value)
            if(NOT "${_feature}" IN_LIST DEPS_USD_FEATURES)
                opendcc_deps_die("opendcc_deps_spec_dependency(${name}): unknown usd feature \"${_feature}\"; "
                                 "known: ${DEPS_USD_FEATURES}")
            endif()
            if(NOT "${_value}" STREQUAL "ON" AND NOT "${_value}" STREQUAL "OFF")
                opendcc_deps_die("opendcc_deps_spec_dependency(${name}): usd feature ${_feature} must be ON or OFF, "
                                 "found \"${_value}\"")
            endif()
        endforeach()
    endif()

    set(DEPS_DECL_${_key}_DECLARED ON
        PARENT_SCOPE)
    foreach(_field ENABLED PROVIDER FORMULA VERSION EXPECT URL SHA256 STRIP PREFIX ALIGN)
        if(DEFINED arg_${_field})
            set(DEPS_DECL_${_key}_${_field} "${arg_${_field}}"
                PARENT_SCOPE)
        endif()
    endforeach()
    foreach(_field CMAKE_VARS FEATURES)
        if(DEFINED arg_${_field})
            opendcc_deps_merge_kv(_merged "${DEPS_DECL_${_key}_${_field}}" "${arg_${_field}}")
            set(DEPS_DECL_${_key}_${_field} "${_merged}"
                PARENT_SCOPE)
        endif()
    endforeach()
endfunction()

# Field reader for a dependency declaration: opendcc_deps_decl(<out> <name> <FIELD>).
function(opendcc_deps_decl out name field)
    opendcc_deps_key(_key "${name}")
    set(${out} "${DEPS_DECL_${_key}_${field}}" PARENT_SCOPE)
endfunction()

function(opendcc_deps_dep_enabled out name)
    opendcc_deps_decl(_enabled "${name}" ENABLED)
    if("${_enabled}" STREQUAL "ON")
        set(${out} ON PARENT_SCOPE)
    else()
        set(${out} OFF PARENT_SCOPE)
    endif()
endfunction()

# Whether an external dependency's own versions replace the spec's (default) or are checked against it.
function(opendcc_deps_dep_align out name)
    opendcc_deps_decl(_align "${name}" ALIGN)
    if("${_align}" STREQUAL "OFF")
        set(${out} OFF PARENT_SCOPE)
    else()
        set(${out} ON PARENT_SCOPE)
    endif()
endfunction()

# The provider each dependency has before the overlay runs: what this platform actually knows how to provision. An
# external dependency that turns out to be unavailable falls back to it.
function(opendcc_deps_record_base_providers)
    foreach(_name IN LISTS DEPS_KNOWN_DEPENDENCIES)
        opendcc_deps_key(_key "${_name}")
        set(DEPS_BASE_${_key}_PROVIDER "${DEPS_DECL_${_key}_PROVIDER}" PARENT_SCOPE)
    endforeach()
endfunction()

function(opendcc_deps_base_provider out name)
    opendcc_deps_key(_key "${name}")
    set(${out} "${DEPS_BASE_${_key}_PROVIDER}" PARENT_SCOPE)
endfunction()

# usd feature switch as ON/OFF; anything undeclared is OFF, as in the spec format.
function(opendcc_deps_dep_feature out name feature)
    opendcc_deps_decl(_features "${name}" FEATURES)
    set(_value OFF)
    foreach(_entry IN LISTS _features)
        string(FIND "${_entry}" "=" _split)
        if(_split GREATER -1)
            string(SUBSTRING "${_entry}" 0 ${_split} _key)
            if("${_key}" STREQUAL "${feature}")
                math(EXPR _value_start "${_split}+1")
                string(SUBSTRING "${_entry}" ${_value_start} -1 _value)
            endif()
        endif()
    endforeach()
    set(${out} "${_value}" PARENT_SCOPE)
endfunction()

function(opendcc_deps_opendcc out key)
    string(TOUPPER "${key}" _key)
    set(${out} "${DEPS_SPEC_OPENDCC_${_key}}" PARENT_SCOPE)
endfunction()

# Port of spec.validate(): returns one human-readable string per problem, empty when the merged spec is usable.
function(opendcc_deps_spec_validate out)
    set(_problems "")
    opendcc_deps_rel(_where "${DEPS_SPEC_FILE}")

    if(NOT "${DEPS_SPEC_SCHEMA}" STREQUAL "1")
        opendcc_deps_list_append(_problems "${_where}: \"schema\" must be 1, found '${DEPS_SPEC_SCHEMA}'")
    endif()
    if(NOT "${DEPS_SPEC_PLATFORM}" STREQUAL "${DEPS_PLATFORM_TAG}")
        opendcc_deps_list_append(_problems
             "${_where}: \"platform\" must be \"${DEPS_PLATFORM_TAG}\", found '${DEPS_SPEC_PLATFORM}'")
    endif()

    if("${DEPS_SPEC_PYTHON_VERSION}" STREQUAL "")
        opendcc_deps_list_append(_problems "${_where}: \"python\".version is required")
    endif()

    if("${DEPS_SPEC_QT_VERSION}" STREQUAL "")
        opendcc_deps_list_append(_problems "${_where}: \"qt\".version is required")
    endif()
    if("${DEPS_SPEC_QT_PYSIDE}" STREQUAL "")
        opendcc_deps_list_append(_problems "${_where}: \"qt\".pyside is required")
    endif()
    if(NOT "${DEPS_SPEC_QT_VERSION}" STREQUAL ""
       AND NOT DEPS_SPEC_QT_PYSIDE STREQUAL ""
       AND NOT DEPS_SPEC_QT_VERSION STREQUAL "${DEPS_SPEC_QT_PYSIDE}")
        string(CONCAT _problem "qt.version (${DEPS_SPEC_QT_VERSION}) and qt.pyside (${DEPS_SPEC_QT_PYSIDE}) "
                               "must be the same release in ${_where}")
        opendcc_deps_list_append(_problems "${_problem}")
    endif()

    if(DEPS_SPEC_OCIO_DECLARED AND "${DEPS_SPEC_OCIO_URL}" STREQUAL "")
        opendcc_deps_list_append(_problems "ocio.config must have a \"url\" in ${_where}")
    endif()

    foreach(_name IN LISTS DEPS_KNOWN_DEPENDENCIES)
        opendcc_deps_key(_key "${_name}")
        if(NOT DEPS_DECL_${_key}_DECLARED)
            continue()
        endif()
        set(_enabled "${DEPS_DECL_${_key}_ENABLED}")
        set(_provider "${DEPS_DECL_${_key}_PROVIDER}")
        if(NOT "${_enabled}" STREQUAL "ON" AND NOT "${_enabled}" STREQUAL "OFF")
            opendcc_deps_list_append(_problems "${_name}: \"enabled\" must be ON or OFF in ${_where}")
        endif()
        if(NOT "${_provider}" IN_LIST DEPS_PROVIDERS)
            string(CONCAT _problem "${_name}: \"provider\" must be one of brew, external, headers, manual, source "
                                   "in ${_where}")
            opendcc_deps_list_append(_problems "${_problem}")
            continue()
        endif()
        set(_prefix "${DEPS_DECL_${_key}_PREFIX}")
        set(_align "${DEPS_DECL_${_key}_ALIGN}")
        if("${_provider}" STREQUAL "external")
            if("${_prefix}" STREQUAL "")
                opendcc_deps_list_append(_problems "${_name}: external provider needs a \"prefix\" in ${_where}")
            elseif(NOT IS_ABSOLUTE "${_prefix}")
                opendcc_deps_list_append(_problems
                                         "${_name}: external \"prefix\" must be an absolute path in ${_where}")
            endif()
            if("${DEPS_DECL_${_key}_VERSION}" STREQUAL "")
                opendcc_deps_list_append(
                    _problems "${_name}: external provider needs a \"version\" to align against in ${_where}")
            endif()
        else()
            if(NOT "${_prefix}" STREQUAL "")
                opendcc_deps_list_append(_problems
                                         "${_name}: \"prefix\" is only for the external provider in ${_where}")
            endif()
            if(NOT "${_align}" STREQUAL "")
                opendcc_deps_list_append(_problems
                                         "${_name}: \"align\" is only for the external provider in ${_where}")
            endif()
        endif()
        if("${_provider}" STREQUAL "brew" AND DEPS_DECL_${_key}"${_FORMULA}" STREQUAL "")
            opendcc_deps_list_append(_problems "${_name}: brew provider needs a \"formula\" in ${_where}")
        endif()
        if(("${_provider}" STREQUAL "source" OR "${_provider}" STREQUAL "headers")
           AND _enabled STREQUAL "ON"
           AND DEPS_DECL_${_key}_URL STREQUAL "")
            opendcc_deps_list_append(_problems
                                     "enabled ${_provider} dependency \"${_name}\" has no \"url\" in ${_where}")
        endif()
        if(NOT DEPS_DECL_${_key}"${_EXPECT}" STREQUAL ""
           AND NOT DEPS_DECL_${_key}_VERSION STREQUAL ""
           AND NOT DEPS_DECL_${_key}_VERSION STREQUAL "any")
            opendcc_deps_satisfies(_satisfied _error "${DEPS_DECL_${_key}_EXPECT}" "${DEPS_DECL_${_key}_VERSION}")
            if(NOT _satisfied)
                opendcc_deps_list_append(_problems "${_name}: ${_error}")
            endif()
        endif()
    endforeach()

    opendcc_deps_dep_enabled(_usd_enabled usd)
    if(_usd_enabled)
        foreach(_entry IN LISTS DEPS_USD_FEATURE_DEPS)
            string(FIND "${_entry}" "=" _split)
            string(SUBSTRING "${_entry}" 0 ${_split} _feature)
            math(EXPR _value_start "${_split}+1")
            string(SUBSTRING "${_entry}" ${_value_start} -1 _dependency)
            opendcc_deps_dep_feature(_feature_on usd "${_feature}")
            opendcc_deps_dep_enabled(_dependency_on "${_dependency}")
            if(_feature_on AND NOT _dependency_on)
                string(CONCAT _problem
                       "usd.features.${_feature} requires dependency \"${_dependency}\" (disabled in "
                       "${_where})")
                opendcc_deps_list_append(_problems "${_problem}")
            endif()
        endforeach()
        foreach(_entry IN LISTS DEPS_USD_UNSUPPORTED)
            string(FIND "${_entry}" "=" _split)
            string(SUBSTRING "${_entry}" 0 ${_split} _feature)
            math(EXPR _value_start "${_split}+1")
            string(SUBSTRING "${_entry}" ${_value_start} -1 _reason)
            opendcc_deps_dep_feature(_feature_on usd "${_feature}")
            if(_feature_on)
                opendcc_deps_list_append(_problems "usd.features.${_feature} ${_reason}")
            endif()
        endforeach()
        foreach(_entry IN LISTS DEPS_USD_FEATURE_IMPLIES)
            string(FIND "${_entry}" "=" _split)
            string(SUBSTRING "${_entry}" 0 ${_split} _feature)
            math(EXPR _value_start "${_split}+1")
            string(SUBSTRING "${_entry}" ${_value_start} -1 _implied)
            opendcc_deps_dep_feature(_feature_on usd "${_feature}")
            opendcc_deps_dep_feature(_implied_on usd "${_implied}")
            if(_feature_on AND NOT _implied_on)
                opendcc_deps_list_append(_problems
                                         "usd.features.${_feature} requires usd.features.${_implied} in ${_where}")
            endif()
        endforeach()
    endif()

    opendcc_deps_decl(_pyside_version pyside VERSION)
    if(NOT "${DEPS_SPEC_QT_PYSIDE}" STREQUAL ""
       AND NOT _pyside_version STREQUAL ""
       AND NOT _pyside_version STREQUAL "${DEPS_SPEC_QT_PYSIDE}")
        string(CONCAT _problem "dependencies.pyside.version (${_pyside_version}) must equal qt.pyside "
                               "(${DEPS_SPEC_QT_PYSIDE}) in ${_where}")
        opendcc_deps_list_append(_problems "${_problem}")
    endif()

    foreach(_entry IN LISTS DEPS_DEP_REQUIRES)
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _owner)
        math(EXPR _value_start "${_split}+1")
        string(SUBSTRING "${_entry}" ${_value_start} -1 _required)
        opendcc_deps_dep_enabled(_owner_on "${_owner}")
        if(NOT _owner_on)
            continue()
        endif()
        string(REPLACE "," ";" _required_list "${_required}")
        foreach(_dependency IN LISTS _required_list)
            opendcc_deps_dep_enabled(_dependency_on "${_dependency}")
            if(NOT _dependency_on)
                string(CONCAT _problem
                       "dependency \"${_dependency}\" is required by \"${_owner}\"; enable it or "
                       "disable \"${_owner}\"")
                opendcc_deps_list_append(_problems "${_problem}")
            endif()
        endforeach()
    endforeach()

    foreach(_entry IN LISTS DEPS_OPENDCC_REQUIRES)
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _key)
        math(EXPR _value_start "${_split}+1")
        string(SUBSTRING "${_entry}" ${_value_start} -1 _required)
        opendcc_deps_opendcc(_key_on "${_key}")
        if(NOT _key_on)
            continue()
        endif()
        string(REPLACE "," ";" _required_list "${_required}")
        foreach(_dependency IN LISTS _required_list)
            opendcc_deps_dep_enabled(_dependency_on "${_dependency}")
            if(NOT _dependency_on)
                string(CONCAT _problem "opendcc.${_key} requires dependency \"${_dependency}\" (disabled in "
                                       "${_where})")
                opendcc_deps_list_append(_problems "${_problem}")
            endif()
        endforeach()
    endforeach()

    opendcc_deps_opendcc(_use_ptex use_ptex)
    opendcc_deps_dep_feature(_usd_ptex usd ptex)
    if(NOT "${_use_ptex}" STREQUAL "${_usd_ptex}")
        if(_use_ptex)
            set(_use_ptex_text "true")
        else()
            set(_use_ptex_text "false")
        endif()
        if(_usd_ptex)
            set(_usd_ptex_text "true")
        else()
            set(_usd_ptex_text "false")
        endif()
        string(CONCAT _problem "opendcc.use_ptex (${_use_ptex_text}) and usd.features.ptex (${_usd_ptex_text}) "
                               "must be equal; set both in ${_where}")
        opendcc_deps_list_append(_problems "${_problem}")
    endif()

    set(${out} "${_problems}" PARENT_SCOPE)
endfunction()
