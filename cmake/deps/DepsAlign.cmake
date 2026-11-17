# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# Alignment: what an `external` dependency has to prove before this build may use it. The provider (provision) and
# the reports (check, list) both read the same answers through opendcc_deps_external_problems(), so a prefix that
# configures is exactly a prefix that `check` accepts, and every disagreement names both sides.
#
# Nothing here provisions or mutates a prefix, and nothing dies on a disagreement: problems are collected so `check`
# can list them all. opendcc_deps_external_prefix is the one hard failure, because a dependency declared external
# without a PREFIX has nothing to verify.

# The decisive artifact of each USD feature, relative to the install prefix: present means the install was built with
# the feature, absent means it was not. One entry per feature — this table is read both ways (discover the external
# install's feature set, then check a declared feature set against the same file), so a feature has exactly one
# marker and an install that has it cannot be half-built.
set(DEPS_USD_FEATURE_ARTIFACTS
    "imaging=lib/*usd_hd.*"
    "usd_imaging=lib/*usd_usdImaging.*"
    "usd_tools=lib/*usd_usdAppUtils.*"
    "usdview=lib/python/pxr/Usdviewq/__init__.py"
    "python=lib/python/pxr/__init__.py"
    "gl=lib/*usd_hgiGL.*"
    "metal=lib/*usd_hgiMetal.*"
    "materialx=lib/*usd_hdMtlx.*"
    "openimageio=plugin/usd/hioOiio.*"
    "embree=plugin/usd/hdEmbree.*"
    "alembic=plugin/usd/usdAbc.*"
    "draco=plugin/usd/usdDraco.*"
    "osl=plugin/usd/sdrOsl.*")

# Switches with no artifact of their own in an installed tree: neither discoverable nor verifiable, so the spec's
# value stands and the report says so.
set(DEPS_USD_FEATURE_UNVERIFIABLE opencolorio ptex openvdb hdf5 tests examples tutorials)

# Markers every external install of a dependency must contain; patterns are passed to file(GLOB) in the prefix.
set(DEPS_EXTERNAL_USD_MARKERS "include/pxr/pxr.h" "lib/*usd_usd.*")

# A TBB installation this build adopts from an external USD (see opendcc_deps_usd_bundled_tbb): either layout, oneTBB
# under include/oneapi with versioned libraries or the TBB 2020 line with include/tbb.
set(DEPS_EXTERNAL_TBB_MARKERS "include/tbb" "lib/*tbb*")

# The install prefix an external dependency was built into.
function(opendcc_deps_external_prefix out name)
    opendcc_deps_decl(_prefix "${name}" PREFIX)
    if("${_prefix}" STREQUAL "")
        opendcc_deps_die("dependency \"${name}\" uses the external provider but declares no PREFIX")
    endif()
    # Collapse "..": the spec writes PREFIX relative to its own directory, and every comparison below and the
    # emitted cache entry are otherwise left with a path that only works from where it was written.
    get_filename_component(_prefix "${_prefix}" ABSOLUTE)
    set(${out} "${_prefix}" PARENT_SCOPE)
endfunction()

# What an external USD says about itself: its release from pxr.h, the pins its pxrConfig.cmake records, and the
# feature set its install layout proves. Returned as "key=value" entries — usd.version, tbb.version,
# opensubdiv.version, python.version, usd.feature.<feature>=ON|OFF — so the aligner and any future consumer read one
# answer. A pin pxrConfig does not record is simply absent.
function(opendcc_deps_usd_discovery out out_problems prefix)
    set(_values "")
    set(_problems "")
    opendcc_deps_usd_paths(_include _library _config _genschema _path_problems "${prefix}")
    foreach(_problem IN LISTS _path_problems)
        opendcc_deps_list_append(_problems "${_problem}")
    endforeach()
    opendcc_deps_usd_version(_version _version_problems "${prefix}")
    foreach(_problem IN LISTS _version_problems)
        opendcc_deps_list_append(_problems "${_problem}")
    endforeach()
    if(NOT "${_version}" STREQUAL "")
        opendcc_deps_list_append(_values "usd.version=${_version}")
    endif()

    opendcc_deps_recorded_pins(_pins _pin_problems "${_config}")
    foreach(_entry IN LISTS _pins)
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _name)
        math(EXPR _value_start "${_split}+1")
        string(SUBSTRING "${_entry}" ${_value_start} -1 _value)
        opendcc_deps_list_append(_values "${_name}.version=${_value}")
    endforeach()

    foreach(_entry IN LISTS DEPS_USD_FEATURE_ARTIFACTS)
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _feature)
        math(EXPR _value_start "${_split}+1")
        string(SUBSTRING "${_entry}" ${_value_start} -1 _artifact)
        file(GLOB _found "${prefix}/${_artifact}")
        if("${_found}" STREQUAL "")
            set(_state OFF)
        else()
            set(_state ON)
        endif()
        opendcc_deps_list_append(_values "usd.feature.${_feature}=${_state}")
    endforeach()

    opendcc_deps_usd_bundled_tbb(_tbb "${prefix}" "${_config}")
    if(NOT "${_tbb}" STREQUAL "")
        opendcc_deps_list_append(_values "tbb.bundled=${_tbb}")
    endif()

    set(${out} "${_values}" PARENT_SCOPE)
    set(${out_problems} "${_problems}" PARENT_SCOPE)
endfunction()

# Per-dependency discovery entry point for the aligner: only usd reports anything.
function(opendcc_deps_external_discover_usd out out_problems prefix)
    opendcc_deps_usd_discovery(_values _problems "${prefix}")
    set(${out} "${_values}" PARENT_SCOPE)
    set(${out_problems} "${_problems}" PARENT_SCOPE)
endfunction()

# Every disagreement between an external dependency and this build: <out> gets the problems, <out-notes> the facts
# the provider prints for the operator. Memoized per dependency because `check` asks twice (state and detail) and the
# USD verification spawns otool over the whole install.
function(opendcc_deps_external_problems out out_notes name)
    opendcc_deps_key(_key "${name}")
    get_property(_checked GLOBAL PROPERTY "DEPS_EXTERNAL_CHECKED_${_key}")
    if("${_checked}" STREQUAL "1")
        get_property(_problems GLOBAL PROPERTY "DEPS_EXTERNAL_PROBLEMS_${_key}")
        get_property(_notes GLOBAL PROPERTY "DEPS_EXTERNAL_NOTES_${_key}")
        set(${out} "${_problems}" PARENT_SCOPE)
        set(${out_notes} "${_notes}" PARENT_SCOPE)
        return()
    endif()

    set(_problems "")
    set(_notes "")
    opendcc_deps_external_prefix(_prefix "${name}")
    if(NOT IS_DIRECTORY "${_prefix}")
        opendcc_deps_list_append(_problems "${_prefix} does not exist")
        set(${out} "${_problems}" PARENT_SCOPE)
        set(${out_notes} "${_notes}" PARENT_SCOPE)
        return()
    endif()

    if(DEFINED DEPS_EXTERNAL_${_key}_MARKERS)
        foreach(_marker IN LISTS DEPS_EXTERNAL_${_key}_MARKERS)
            file(GLOB _matches "${_prefix}/${_marker}")
            if("${_matches}" STREQUAL "")
                opendcc_deps_list_append(_problems "${name}: missing ${_marker} in ${_prefix}")
            endif()
        endforeach()
    endif()
    if(COMMAND opendcc_deps_external_verify_${name})
        cmake_language(CALL opendcc_deps_external_verify_${name} _extra _extra_notes "${_prefix}")
        foreach(_problem IN LISTS _extra)
            opendcc_deps_list_append(_problems "${_problem}")
        endforeach()
        foreach(_note IN LISTS _extra_notes)
            opendcc_deps_list_append(_notes "${_note}")
        endforeach()
    endif()

    set_property(GLOBAL PROPERTY "DEPS_EXTERNAL_PROBLEMS_${_key}" "${_problems}")
    set_property(GLOBAL PROPERTY "DEPS_EXTERNAL_NOTES_${_key}" "${_notes}")
    set_property(GLOBAL PROPERTY "DEPS_EXTERNAL_CHECKED_${_key}" 1)
    set(${out} "${_problems}" PARENT_SCOPE)
    set(${out_notes} "${_notes}" PARENT_SCOPE)
endfunction()

# The four locations FindPxrUSD would derive from USD_ROOT, each checked where a run from this prefix needs it. A
# missing one is reported here and returned as its expected location, so the generated cache never emits an empty
# path.
function(opendcc_deps_usd_paths out_include out_library out_config out_genschema out_problems prefix)
    set(_problems "")

    set(_include "${prefix}/include")
    if(NOT EXISTS "${prefix}/include/pxr/pxr.h")
        opendcc_deps_list_append(_problems "external USD ${prefix} has no include/pxr/pxr.h")
    endif()

    set(_library "${prefix}/lib")
    file(GLOB _libraries "${prefix}/lib/lib*usd_usd.*")
    if("${_libraries}" STREQUAL "")
        opendcc_deps_list_append(_problems "external USD ${prefix} has no lib/lib*usd_usd.*")
    endif()

    set(_config "")
    foreach(_candidate "${prefix}/pxrConfig.cmake" "${prefix}/lib/cmake/pxr/pxrConfig.cmake"
                       "${prefix}/cmake/pxrConfig.cmake")
        if("${_config}" STREQUAL "" AND EXISTS "${_candidate}")
            set(_config "${_candidate}")
        endif()
    endforeach()
    if("${_config}" STREQUAL "")
        set(_config "${prefix}/pxrConfig.cmake")
        opendcc_deps_list_append(_problems "external USD ${prefix} has no pxrConfig.cmake")
    endif()

    set(_genschema "")
    foreach(_candidate "${prefix}/bin/usdGenSchema" "${prefix}/lib/python/pxr/Usd/usdGenSchema.py")
        if("${_genschema}" STREQUAL "" AND EXISTS "${_candidate}")
            set(_genschema "${_candidate}")
        endif()
    endforeach()
    if("${_genschema}" STREQUAL "")
        set(_genschema "${prefix}/bin/usdGenSchema")
        opendcc_deps_list_append(_problems "external USD ${prefix} has no bin/usdGenSchema")
    endif()

    set(${out_include} "${_include}" PARENT_SCOPE)
    set(${out_library} "${_library}" PARENT_SCOPE)
    set(${out_config} "${_config}" PARENT_SCOPE)
    set(${out_genschema} "${_genschema}" PARENT_SCOPE)
    set(${out_problems} "${_problems}" PARENT_SCOPE)
endfunction()

# The spec's version string is the one the release is named after ("25.08"), which pxr.h carries as the year and
# month of PXR_MINOR_VERSION and PXR_PATCH_VERSION.
function(opendcc_deps_usd_version out out_problems prefix)
    set(_version "")
    set(_problems "")
    if(EXISTS "${prefix}/include/pxr/pxr.h")
        file(STRINGS "${prefix}/include/pxr/pxr.h" _lines REGEX "^#define PXR_(MAJOR|MINOR|PATCH)_VERSION ")
        set(_minor "")
        set(_patch "")
        foreach(_line IN LISTS _lines)
            if("${_line}" MATCHES "PXR_MINOR_VERSION ([0-9]+)")
                set(_minor "${CMAKE_MATCH_1}")
            elseif("${_line}" MATCHES "PXR_PATCH_VERSION ([0-9]+)")
                set(_patch "${CMAKE_MATCH_1}")
            endif()
        endforeach()
        if(NOT "${_minor}" STREQUAL "" AND NOT "${_patch}" STREQUAL "")
            set(_version "${_minor}.${_patch}")
        endif()
    endif()
    if("${_version}" STREQUAL "")
        opendcc_deps_list_append(_problems "external USD ${prefix} has no PXR_*_VERSION in include/pxr/pxr.h")
    endif()
    set(${out} "${_version}" PARENT_SCOPE)
    set(${out_problems} "${_problems}" PARENT_SCOPE)
endfunction()

# The versions pxrConfig.cmake demands of its own dependencies, as "name=value" entries. A USD built without a pin
# records none, and then there is nothing to compare. The TBB line lives in the branch USD takes only when it was
# configured with a TBB config package; with `PXR_FIND_TBB_IN_CONFIG "OFF"` it is dead text and the installation ships
# its own TBB instead, which opendcc_deps_usd_bundled_tbb reports.
function(opendcc_deps_recorded_pins out out_problems config)
    set(_pins "")
    if(EXISTS "${config}")
        file(READ "${config}" _text)
        if("${_text}" MATCHES "find_dependency[(]Python3 \"([^\"]+)\"")
            opendcc_deps_list_append(_pins "python=${CMAKE_MATCH_1}")
        endif()
        if("${_text}" MATCHES "find_dependency[(]TBB ([^ \t\n)]+) CONFIG")
            set(_tbb_pin "${CMAKE_MATCH_1}")
            if(NOT "${_text}" MATCHES "set[(]PXR_FIND_TBB_IN_CONFIG \"OFF\"[)]")
                opendcc_deps_list_append(_pins "tbb=${_tbb_pin}")
            endif()
        endif()
        if("${_text}" MATCHES "find_dependency[(]OpenSubdiv ([^ \t\n)]+) CONFIG")
            opendcc_deps_list_append(_pins "opensubdiv=${CMAKE_MATCH_1}")
        endif()
    endif()
    set(${out} "${_pins}" PARENT_SCOPE)
    set(${out_problems} "" PARENT_SCOPE)
endfunction()

# The TBB an external USD was compiled against when its pxrConfig declares the import itself instead of finding a TBB
# config — `PXR_FIND_TBB_IN_CONFIG "OFF"`, USD's default for a TBB it ships, in which case pxrConfig points
# TBB::tbb at the installation. That TBB is part of USD's ABI, not a version floor: pxr's public headers instantiate
# the TBB API of that build, and TBB has no compatibility across the oneTBB boundary (`tbb::task` is gone from
# oneTBB 2021), so compiling them against another TBB fails or silently disagrees with libusd_work. Reports the
# installed version, empty when USD found a config package or ships no TBB of its own.
function(opendcc_deps_usd_bundled_tbb out prefix config)
    set(_version "")
    if(NOT EXISTS "${prefix}/include/tbb" OR NOT EXISTS "${config}")
        set(${out} "" PARENT_SCOPE)
        return()
    endif()
    file(READ "${config}" _text)
    if(NOT "${_text}" MATCHES "set[(]PXR_FIND_TBB_IN_CONFIG \"OFF\"[)]")
        set(${out} "" PARENT_SCOPE)
        return()
    endif()
    # oneTBB names the version in oneapi/tbb/version.h, the TBB 2020 line in tbb/tbb_stddef.h.
    foreach(_header "${prefix}/include/oneapi/tbb/version.h" "${prefix}/include/tbb/tbb_stddef.h")
        if("${_version}" STREQUAL "" AND EXISTS "${_header}")
            set(_minor "")
            set(_major "")
            file(STRINGS "${_header}" _lines REGEX "^#define TBB_VERSION_(MAJOR|MINOR) ")
            foreach(_line IN LISTS _lines)
                if("${_line}" MATCHES "TBB_VERSION_MAJOR ([0-9]+)")
                    set(_major "${CMAKE_MATCH_1}")
                elseif("${_line}" MATCHES "TBB_VERSION_MINOR ([0-9]+)")
                    set(_minor "${CMAKE_MATCH_1}")
                endif()
            endforeach()
            if(NOT "${_major}" STREQUAL "" AND NOT "${_minor}" STREQUAL "")
                set(_version "${_major}.${_minor}")
            endif()
        endif()
    endforeach()
    set(${out} "${_version}" PARENT_SCOPE)
endfunction()

# "3.12.16" for an interpreter that answers, empty otherwise.
function(opendcc_deps_interpreter_version out python)
    set(_version "")
    if(NOT "${python}" STREQUAL "" AND EXISTS "${python}")
        execute_process(
            COMMAND "${python}" -c "import sys;print(sys.version.split()[0])"
            OUTPUT_VARIABLE _stdout
            ERROR_QUIET
            RESULT_VARIABLE _code
            OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(_code EQUAL 0)
            set(_version "${_stdout}")
        endif()
    endif()
    set(${out} "${_version}" PARENT_SCOPE)
endfunction()

# major.minor of the interpreter this build embeds, memoized: the linkage judgement asks once per binary.
function(opendcc_deps_align_interpreter out)
    get_property(_cached GLOBAL PROPERTY DEPS_ALIGN_VENV_PYTHON_SHORT)
    if(NOT "${_cached}" STREQUAL "")
        set(${out} "${_cached}" PARENT_SCOPE)
        return()
    endif()
    opendcc_deps_platform_venv_python(_python "${DEPS_PREFIX}")
    opendcc_deps_interpreter_version(_version "${_python}")
    set(_short "")
    if("${_version}" MATCHES "^([0-9]+[.][0-9]+)")
        set(_short "${CMAKE_MATCH_1}")
        set_property(GLOBAL PROPERTY DEPS_ALIGN_VENV_PYTHON_SHORT "${_short}")
    endif()
    set(${out} "${_short}" PARENT_SCOPE)
endfunction()

# `otool -L` text into "basename<TAB>path" entries. The variable *names* the text so a fixture can supply multi-line
# input; the first reference line is the binary's own install name and is dropped.
function(opendcc_deps_reference_list out text_var out_problems)
    string(ASCII 9 _tab)
    set(_refs "")
    set(_text "${${text_var}}")
    string(REPLACE "\r\n" "\n" _text "${_text}")
    string(REPLACE "\n" ";" _lines "${_text}")
    set(_seen 0)
    foreach(_line IN LISTS _lines)
        string(FIND "${_line}" "${_tab}" _tab_position)
        if(NOT _tab_position EQUAL 0)
            continue()
        endif()
        string(SUBSTRING "${_line}" 1 -1 _entry)
        string(REGEX REPLACE " \\(compatibility.*$" "" _path "${_entry}")
        string(STRIP "${_path}" _path)
        if("${_path}" STREQUAL "")
            continue()
        endif()
        math(EXPR _seen "${_seen}+1")
        if(_seen EQUAL 1)
            continue()
        endif()
        get_filename_component(_basename "${_path}" NAME)
        opendcc_deps_list_append(_refs "${_basename}${_tab}${_path}")
    endforeach()
    set(${out} "${_refs}" PARENT_SCOPE)
    set(${out_problems} "" PARENT_SCOPE)
endfunction()

# References of one binary; on a host without otool (no spec exists there today) the judgement is skipped.
function(opendcc_deps_binary_references out out_problems binary)
    set(_refs "")
    set(_problems "")
    if(CMAKE_HOST_APPLE)
        execute_process(
            COMMAND otool -L "${binary}"
            OUTPUT_VARIABLE _text
            ERROR_QUIET
            RESULT_VARIABLE _code)
        if("${_code}" STREQUAL "0")
            opendcc_deps_reference_list(_refs _text _problems)
        endif()
    endif()
    set(${out} "${_refs}" PARENT_SCOPE)
    set(${out_problems} "${_problems}" PARENT_SCOPE)
endfunction()

# Strip a shared-library suffix and every trailing ".N": libtbb.12.dylib -> libtbb, libImath-3_1.29.dylib ->
# libImath-3_1.
function(opendcc_deps_lib_stem out basename)
    set(_stem "${basename}")
    string(REGEX REPLACE "[.](dylib|so)$" "" _stem "${_stem}")
    while("${_stem}" MATCHES "[.][0-9]+$")
        string(REGEX REPLACE "[.][0-9]+$" "" _stem "${_stem}")
    endwhile()
    set(${out} "${_stem}" PARENT_SCOPE)
endfunction()

# What every enabled dependency offers as libraries, as "basename=<dependency>" entries, plus the same indexed by
# opendcc_deps_lib_stem. Resolved without dying: a formula that is not installed simply contributes nothing (that is
# the provider's complaint to make, not this judgement's).
function(opendcc_deps_dependency_library_index out_exact out_stems)
    set(_exact "")
    set(_stems "")
    foreach(_name IN LISTS DEPS_KNOWN_DEPENDENCIES)
        opendcc_deps_dep_enabled(_enabled "${_name}")
        if(NOT _enabled)
            continue()
        endif()
        opendcc_deps_decl(_provider "${_name}" PROVIDER)
        if("${_provider}" STREQUAL "brew")
            opendcc_deps_decl(_formula "${_name}" FORMULA)
            opendcc_deps_brew_prefix(_directory "${_formula}")
        elseif("${_provider}" STREQUAL "source" OR "${_provider}" STREQUAL "headers")
            set(_directory "${DEPS_PREFIX}")
        elseif("${_provider}" STREQUAL "external")
            opendcc_deps_external_prefix(_directory "${_name}")
        else()
            continue()
        endif()
        if("${_directory}" STREQUAL "" OR NOT IS_DIRECTORY "${_directory}/lib")
            continue()
        endif()
        file(GLOB _libraries LIST_DIRECTORIES false "${_directory}/lib/*")
        foreach(_library IN LISTS _libraries)
            get_filename_component(_basename "${_library}" NAME)
            opendcc_deps_list_append(_exact "${_basename}=${_name}")
            opendcc_deps_lib_stem(_stem "${_basename}")
            opendcc_deps_list_append(_stems "${_stem}=${_name}")
        endforeach()
    endforeach()
    if(NOT "${_exact}" STREQUAL "")
        list(REMOVE_DUPLICATES _exact)
    endif()
    if(NOT "${_stems}" STREQUAL "")
        list(REMOVE_DUPLICATES _stems)
    endif()
    set(${out_exact} "${_exact}" PARENT_SCOPE)
    set(${out_stems} "${_stems}" PARENT_SCOPE)
endfunction()

# Judge the references named by <refs_var> against the indexes named by <exact_var>/<stems_var>: USD's own libraries,
# system libraries and libraries private to the external prefix are skipped; everything else has to be provided by an
# enabled dependency with the same soname, or be the Python the build embeds.
function(opendcc_deps_link_alignment out refs_var external_prefix exact_var stems_var)
    set(_problems "")
    string(ASCII 9 _tab)
    set(_exact "${${exact_var}}")
    set(_stems "${${stems_var}}")

    foreach(_entry IN LISTS _exact)
        string(FIND "${_entry}" "=" _cut)
        string(SUBSTRING "${_entry}" 0 ${_cut} _name)
        math(EXPR _next "${_cut}+1")
        string(SUBSTRING "${_entry}" ${_next} -1 _dependency)
        set("DEPS_ALIGN_EXACT_${_name}" "${_dependency}")
        opendcc_deps_list_append("DEPS_ALIGN_PROVIDES_${_dependency}" "${_name}")
    endforeach()
    foreach(_entry IN LISTS _stems)
        string(FIND "${_entry}" "=" _cut)
        string(SUBSTRING "${_entry}" 0 ${_cut} _name)
        math(EXPR _next "${_cut}+1")
        string(SUBSTRING "${_entry}" ${_next} -1 _dependency)
        set("DEPS_ALIGN_STEM_${_name}" "${_dependency}")
    endforeach()

    foreach(_reference IN LISTS ${refs_var})
        string(FIND "${_reference}" "${_tab}" _split)
        if(_split LESS 0)
            continue()
        endif()
        string(SUBSTRING "${_reference}" 0 ${_split} _basename)
        math(EXPR _path_start "${_split}+1")
        string(SUBSTRING "${_reference}" ${_path_start} -1 _path)

        if("${_basename}" MATCHES "^libusd_")
            continue()
        endif()
        if("${_path}" MATCHES "^/usr/lib/" OR "${_path}" MATCHES "^/System/")
            continue()
        endif()

        set(_python "")
        if("${_path}" MATCHES "/Python[.]framework/Versions/([0-9]+[.][0-9]+)/")
            set(_python "${CMAKE_MATCH_1}")
        elseif("${_basename}" MATCHES "^libpython([0-9]+[.][0-9]+)")
            set(_python "${CMAKE_MATCH_1}")
        endif()
        if(NOT "${_python}" STREQUAL "")
            opendcc_deps_align_interpreter(_embedded)
            if(NOT "${_embedded}" STREQUAL "" AND NOT "${_python}" STREQUAL "${_embedded}")
                opendcc_deps_list_append(
                    _problems "external USD links Python ${_python} but the build embeds ${_embedded}")
            endif()
            continue()
        endif()

        set(_dependency "${DEPS_ALIGN_EXACT_${_basename}}")
        if(NOT "${_dependency}" STREQUAL "")
            continue()
        endif()
        opendcc_deps_lib_stem(_stem "${_basename}")
        set(_dependency "${DEPS_ALIGN_STEM_${_stem}}")
        if(NOT "${_dependency}" STREQUAL "")
            set(_ours "${DEPS_ALIGN_PROVIDES_${_dependency}}")
            string(JOIN ", " _ours_text ${_ours})
            opendcc_deps_list_append(
                _problems
                "external USD links ${_basename} (${_path}); dependency \"${_dependency}\" provides ${_ours_text}")
            continue()
        endif()

        if("${_path}" MATCHES "^@rpath/(.+)$")
            set(_rpath_name "${CMAKE_MATCH_1}")
            if(EXISTS "${external_prefix}/lib/${_rpath_name}")
                continue()
            endif()
        endif()
        string(FIND "${_path}" "${external_prefix}/" _inside)
        if(_inside EQUAL 0)
            continue()
        endif()
        opendcc_deps_list_append(
            _problems "external USD links ${_basename} (${_path}) which no enabled dependency provides")
    endforeach()

    set(${out} "${_problems}" PARENT_SCOPE)
endfunction()

# Import what this build uses from the external USD with the interpreter the build embeds: the modules and the
# libraries have to be loadable before any of it is put on a link line.
function(opendcc_deps_usd_python_probe out prefix python)
    set(_problems "")
    opendcc_deps_dep_feature(_python_on usd python)
    if(NOT _python_on)
        set(${out} "${_problems}" PARENT_SCOPE)
        return()
    endif()
    if("${python}" STREQUAL "" OR NOT EXISTS "${python}")
        opendcc_deps_list_append(
            _problems "the dependency venv is not provisioned; run cmake --preset ${DEPS_PLATFORM_TAG}-deps")
        set(${out} "${_problems}" PARENT_SCOPE)
        return()
    endif()

    set(_code "import pxr; from pxr import Usd, UsdGeom, UsdShade")
    opendcc_deps_dep_feature(_imaging_on usd usd_imaging)
    if(_imaging_on)
        string(APPEND _code ", UsdImagingGL")
    endif()
    string(APPEND _code "; print(pxr.__file__)")

    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env "PYTHONPATH=${prefix}/lib/python" "DYLD_LIBRARY_PATH=${prefix}/lib"
                "${python}" -c "${_code}"
        OUTPUT_VARIABLE _stdout
        ERROR_VARIABLE _stderr
        RESULT_VARIABLE _code_result)
    if(NOT "${_code_result}" STREQUAL "0")
        string(REPLACE "\r\n" "\n" _stderr "${_stderr}")
        string(REPLACE "\n" ";" _lines "${_stderr}")
        set(_shown "")
        foreach(_line IN LISTS _lines)
            string(STRIP "${_line}" _line)
            if(NOT "${_line}" STREQUAL "")
                opendcc_deps_list_append(_shown "${_line}")
            endif()
            list(LENGTH _shown _shown_count)
            if(_shown_count GREATER 5)
                break()
            endif()
        endforeach()
        string(JOIN "\n" _shown_text ${_shown})
        opendcc_deps_list_append(
            _problems "the external USD's python modules do not import with ${python}:\n${_shown_text}")
    endif()
    set(${out} "${_problems}" PARENT_SCOPE)
endfunction()

# Everything the external USD has to agree with this build on: where it is, which release it is, the versions
# pxrConfig.cmake records for Python/TBB/OpenSubdiv, the artifacts of every feature the spec enables, the libraries
# its binaries reference, and that it imports with our interpreter.
function(opendcc_deps_external_verify_usd out out_notes prefix)
    set(_problems "")
    set(_notes "")

    opendcc_deps_usd_paths(_include _library _config _genschema _path_problems "${prefix}")
    foreach(_problem IN LISTS _path_problems)
        opendcc_deps_list_append(_problems "${_problem}")
    endforeach()

    opendcc_deps_usd_version(_version _version_problems "${prefix}")
    foreach(_problem IN LISTS _version_problems)
        opendcc_deps_list_append(_problems "${_problem}")
    endforeach()
    if(NOT "${_version}" STREQUAL "")
        opendcc_deps_decl(_pin usd VERSION)
        opendcc_deps_version_matches(_matches "${_pin}" "${_version}")
        if(_matches)
            opendcc_deps_list_append(_notes "usd ${_version} (${prefix})")
        else()
            opendcc_deps_list_append(
                _problems "external USD ${prefix} is ${_version}; the spec pins usd.VERSION ${_pin}")
        endif()
    endif()

    opendcc_deps_platform_venv_python(_python "${DEPS_PREFIX}")
    opendcc_deps_interpreter_version(_venv_version "${_python}")
    set(_venv_short "")
    if("${_venv_version}" MATCHES "^([0-9]+[.][0-9]+)")
        set(_venv_short "${CMAKE_MATCH_1}")
    endif()

    opendcc_deps_recorded_pins(_pins _pin_problems "${_config}")
    foreach(_entry IN LISTS _pins)
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _name)
        math(EXPR _value_start "${_split}+1")
        string(SUBSTRING "${_entry}" ${_value_start} -1 _value)
        if("${_name}" STREQUAL "python")
            opendcc_deps_list_append(_notes "python ${_value}")
            if(NOT "${_venv_short}" STREQUAL "")
                string(REPLACE "." "[.]" _venv_pattern "${_venv_short}")
                if(NOT "${_value}" MATCHES "^${_venv_pattern}([.]|$)")
                    string(CONCAT _problem
                                  "external USD was built against Python ${_value} (pxrConfig.cmake); the venv "
                                  "interpreter is ${_venv_version}")
                    opendcc_deps_list_append(_problems "${_problem}")
                endif()
            endif()
        elseif("${_name}" STREQUAL "tbb" OR "${_name}" STREQUAL "opensubdiv")
            opendcc_deps_list_append(_notes "${_name} ${_value}")
            opendcc_deps_decl(_spec_pin "${_name}" VERSION)
            # The recorded version is a minimum: the spec may pin something newer, but not something older.
            opendcc_deps_version_at_least(_satisfied "${_spec_pin}" "${_value}")
            if(NOT _satisfied)
                if("${_name}" STREQUAL "tbb")
                    set(_shown "TBB")
                else()
                    set(_shown "OpenSubdiv")
                endif()
                opendcc_deps_list_append(
                    _problems
                    "external USD needs ${_shown} >= ${_value} (pxrConfig.cmake); the spec pins ${_spec_pin}")
            endif()
        endif()
    endforeach()

    # A TBB the installation ships is not a floor: this build has to use that copy, and only alignment can move the
    # dependency there. `ALIGN OFF` keeps the spec authoritative, so that is what it reports.
    opendcc_deps_usd_bundled_tbb(_bundled_tbb "${prefix}" "${_config}")
    if(NOT "${_bundled_tbb}" STREQUAL "")
        opendcc_deps_decl(_tbb_provider tbb PROVIDER)
        set(_tbb_prefix "")
        if("${_tbb_provider}" STREQUAL "external")
            opendcc_deps_external_prefix(_tbb_prefix tbb)
        endif()
        if(NOT "${_tbb_prefix}" STREQUAL "${prefix}")
            string(CONCAT _problem
                          "external USD ships TBB ${_bundled_tbb} and its headers instantiate that API; the spec "
                          "provisions tbb with provider \"${_tbb_provider}\". Declare tbb PROVIDER external PREFIX "
                          "${prefix} — alignment does that on its own")
            opendcc_deps_list_append(_problems "${_problem}")
        else()
            opendcc_deps_list_append(_notes "tbb ${_bundled_tbb} (${prefix})")
        endif()
    endif()

    foreach(_entry IN LISTS DEPS_USD_FEATURE_ARTIFACTS)
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _feature)
        math(EXPR _value_start "${_split}+1")
        string(SUBSTRING "${_entry}" ${_value_start} -1 _artifact)
        opendcc_deps_dep_feature(_on usd "${_feature}")
        if(NOT _on)
            continue()
        endif()
        file(GLOB _found "${prefix}/${_artifact}")
        if("${_found}" STREQUAL "")
            opendcc_deps_list_append(
                _problems
                "usd.features.${_feature} is ON but ${prefix}/${_artifact} is missing from the external USD")
        endif()
    endforeach()

    opendcc_deps_dependency_library_index(_exact _stems)
    file(GLOB _binaries LIST_DIRECTORIES false "${prefix}/lib/lib*usd_*")
    file(GLOB _plugins LIST_DIRECTORIES false "${prefix}/plugin/usd/*")
    set(_linkage "")
    foreach(_binary IN LISTS _binaries _plugins)
        opendcc_deps_binary_references(_refs _reference_problems "${_binary}")
        opendcc_deps_link_alignment(_link_problems _refs "${prefix}" _exact _stems)
        foreach(_problem IN LISTS _link_problems)
            opendcc_deps_list_append(_linkage "${_problem}")
        endforeach()
    endforeach()
    # The same missing soname shows up in dozens of libusd_* binaries; say it once.
    if(NOT "${_linkage}" STREQUAL "")
        list(REMOVE_DUPLICATES _linkage)
    endif()
    foreach(_problem IN LISTS _linkage)
        opendcc_deps_list_append(_problems "${_problem}")
    endforeach()

    foreach(_feature IN LISTS DEPS_USD_FEATURE_UNVERIFIABLE)
        opendcc_deps_dep_feature(_on usd "${_feature}")
        if(_on)
            opendcc_deps_list_append(_notes "usd.features.${_feature} cannot be verified from an install layout")
        endif()
    endforeach()

    opendcc_deps_usd_python_probe(_probe_problems "${prefix}" "${_python}")
    foreach(_problem IN LISTS _probe_problems)
        opendcc_deps_list_append(_problems "${_problem}")
    endforeach()

    set(${out} "${_problems}" PARENT_SCOPE)
    set(${out_notes} "${_notes}" PARENT_SCOPE)
endfunction()

# Report state of an external dependency: the prefix is absent, present but disagreeing, or usable.
function(opendcc_deps_external_state out out_problems name)
    opendcc_deps_external_prefix(_prefix "${name}")
    if(NOT IS_DIRECTORY "${_prefix}")
        set(${out} "missing" PARENT_SCOPE)
        set(${out_problems} "" PARENT_SCOPE)
        return()
    endif()
    opendcc_deps_external_problems(_problems _notes "${name}")
    if("${_problems}" STREQUAL "")
        set(${out} "ok" PARENT_SCOPE)
    else()
        set(${out} "mismatch" PARENT_SCOPE)
    endif()
    set(${out_problems} "${_problems}" PARENT_SCOPE)
endfunction()

# ----------------------------------------------------------------------------------------------------------
# alignment: the external install is authoritative, the spec follows it
#
# Verification (above) answers "does this build match my spec". Alignment answers the reverse question and is what
# an `external` dependency does by default: the discovered versions are written into the merged spec before
# validation, so provisioning, the generated cache and the application build all describe that installation. Every
# adopted value is reported; `ALIGN OFF` keeps the strict verifier instead.

# ----------------------------------------------------------------------------------------------------------
# alignment: the external install is authoritative, the spec follows it
#
# Verification (above) answers "does this build match my spec". Alignment answers the reverse question and is what
# an `external` dependency does by default: the discovered versions are written into the merged spec before
# validation, so provisioning, the generated cache and the application build all describe that installation. Every
# adopted value is reported; `ALIGN OFF` keeps the strict verifier instead.
#
# Changes accumulate in two global properties instead of being threaded through output variables: each adoption is
# decided several calls deep (version -> expect, feature -> feature list) and a variable name passed down that far
# only ever reaches the immediately enclosing scope.

# Pack one "set a spec variable" instruction so a value containing ';' (a feature list) survives the trip back to the
# spec scope.
function(opendcc_deps_align_assign out variable value)
    set(${out} "${variable}${DEPS_US}${value}" PARENT_SCOPE)
endfunction()

# Record that <variable> has to become <value> in the spec.
function(opendcc_deps_align_remember variable value)
    get_property(_entries GLOBAL PROPERTY DEPS_ALIGN_ASSIGNMENTS)
    opendcc_deps_align_assign(_entry "${variable}" "${value}")
    opendcc_deps_list_append(_entries "${_entry}")
    set_property(GLOBAL PROPERTY DEPS_ALIGN_ASSIGNMENTS "${_entries}")
endfunction()

function(opendcc_deps_align_note)
    get_property(_notes GLOBAL PROPERTY DEPS_ALIGN_NOTES)
    opendcc_deps_list_append(_notes "${ARGV0}")
    set_property(GLOBAL PROPERTY DEPS_ALIGN_NOTES "${_notes}")
endfunction()

# Drop an EXPECT range the adopted version falls outside: a range states what this build supports, and an
# installation we do not build is not something we can claim to support.
function(opendcc_deps_align_expect name value)
    opendcc_deps_key(_key "${name}")
    set(_expect "${DEPS_DECL_${_key}_EXPECT}")
    if("${_expect}" STREQUAL "" OR "${_expect}" STREQUAL "any")
        return()
    endif()
    opendcc_deps_satisfies(_satisfied _error "${_expect}" "${value}")
    if(_satisfied)
        return()
    endif()
    opendcc_deps_align_remember("DEPS_DECL_${_key}_EXPECT" "any")
    opendcc_deps_align_note("${name}.EXPECT \"${_expect}\" -> \"any\" (the external build defines the version)")
endfunction()

# Adopt <value> as the VERSION of dependency <name>.
function(opendcc_deps_align_dependency_version name value)
    opendcc_deps_key(_key "${name}")
    set(_pin "${DEPS_DECL_${_key}_VERSION}")
    if(NOT "${_pin}" STREQUAL "${value}")
        opendcc_deps_align_remember("DEPS_DECL_${_key}_VERSION" "${value}")
        if("${_pin}" STREQUAL "")
            set(_pin "(unset)")
        endif()
        opendcc_deps_align_note("${name}.VERSION ${_pin} -> ${value}")
    endif()
    opendcc_deps_align_expect("${name}" "${value}")
endfunction()

# A version pxrConfig records for a library it links is a *minimum*: `find_dependency(TBB 2020.3 CONFIG)` is satisfied
# by every newer TBB, and a keg newer than the external build is what the spec provisions besides. Downgrading is not
# something brew can do, so keep the spec's version when it already satisfies the floor and adopt it only when it is
# older.
function(opendcc_deps_align_dependency_floor name floor)
    opendcc_deps_key(_key "${name}")
    set(_pin "${DEPS_DECL_${_key}_VERSION}")
    opendcc_deps_version_at_least(_satisfied "${_pin}" "${floor}")
    if(_satisfied)
        if(NOT "${_pin}" STREQUAL "${floor}")
            opendcc_deps_align_note("${name}.VERSION ${_pin} kept (the external USD requires >= ${floor})")
        endif()
        return()
    endif()
    opendcc_deps_align_dependency_version("${name}" "${floor}")
endfunction()

# Move a dependency to the installation an external dependency ships it in: provider external, that prefix, and the
# version found there. This is not a floor — the external build's copy is the only one it can be used with (see
# opendcc_deps_usd_bundled_tbb) — so the spec's own pin is replaced rather than checked.
function(opendcc_deps_align_dependency_external name prefix version)
    opendcc_deps_key(_key "${name}")
    set(_provider "${DEPS_DECL_${_key}_PROVIDER}")
    set(_current "${DEPS_DECL_${_key}_PREFIX}")
    if(NOT "${_provider}" STREQUAL "external" OR NOT "${_current}" STREQUAL "${prefix}")
        if("${_provider}" STREQUAL "external")
            set(_shown "${_current}")
        else()
            set(_shown "${_provider}")
        endif()
        opendcc_deps_align_remember("DEPS_DECL_${_key}_PROVIDER" "external")
        opendcc_deps_align_remember("DEPS_DECL_${_key}_PREFIX" "${prefix}")
        string(CONCAT _note
                      "${name} ${_shown} -> external ${prefix} (the external USD is built against ${name} ${version} "
                      "and its headers instantiate that API)")
        opendcc_deps_align_note("${_note}")
    endif()
    opendcc_deps_align_dependency_version("${name}" "${version}")
endfunction()

# Python reaches the build twice: the `python` dependency (a brew keg) and the top-level python block (the venv the
# application and the pxr modules run in). Both have to follow the interpreter the external USD was built against.
# Only major.minor is a pin we can hold: the patch comes from the keg brew provides, and pinning the exact patch an
# external build happened to use would fail on every keg bump (and cannot be reached by upgrading).
function(opendcc_deps_align_python value)
    opendcc_deps_key(_key python)
    set(_minor_version "")
    if("${value}" MATCHES "^([0-9]+[.][0-9]+)")
        set(_minor_version "${CMAKE_MATCH_1}")
    else()
        set(_minor_version "${value}")
    endif()

    set(_pin "${DEPS_DECL_${_key}_VERSION}")
    opendcc_deps_version_matches(_satisfied "${_minor_version}" "${_pin}")
    if(NOT _satisfied)
        opendcc_deps_align_remember("DEPS_DECL_${_key}_VERSION" "${_minor_version}")
        if("${_pin}" STREQUAL "")
            set(_pin "(unset)")
        endif()
        opendcc_deps_align_note(
            "python.VERSION ${_pin} -> ${_minor_version} (the external USD was built against ${value})")
    endif()
    opendcc_deps_align_expect(python "${_minor_version}")

    if(NOT "${DEPS_SPEC_PYTHON_VERSION}" STREQUAL "${_minor_version}")
        opendcc_deps_align_remember("DEPS_SPEC_PYTHON_VERSION" "${_minor_version}")
        string(CONCAT _note
                      "python VERSION ${DEPS_SPEC_PYTHON_VERSION} -> ${_minor_version} (the venv is recreated and "
                      "everything built against it rebuilds)")
        opendcc_deps_align_note("${_note}")
    endif()

    # Only a formula that already names a Python version can be retargeted; an operator pointing the dependency at
    # something else keeps that choice.
    set(_formula "${DEPS_DECL_${_key}_FORMULA}")
    if(NOT "${_formula}" MATCHES "^python@[0-9.]+$")
        return()
    endif()
    set(_formula_new "python@${_minor_version}")
    if("${_formula}" STREQUAL "${_formula_new}")
        return()
    endif()
    opendcc_deps_align_remember("DEPS_DECL_${_key}_FORMULA" "${_formula_new}")
    opendcc_deps_align_remember("DEPS_SPEC_PYTHON_FORMULA" "${_formula_new}")
    opendcc_deps_align_note("python FORMULA ${_formula} -> ${_formula_new}")
endfunction()

# Turn one dependency's discovered "key=value" entries into spec assignments plus one note per change. <prefix> is
# the installation they were read from, which a bundled dependency is then addressed through.
function(opendcc_deps_align_values name values_var prefix)
    set(_features "${DEPS_DECL_USD_FEATURES}")
    set(_features_changed OFF)

    foreach(_entry IN LISTS ${values_var})
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _field)
        math(EXPR _value_start "${_split}+1")
        string(SUBSTRING "${_entry}" ${_value_start} -1 _value)

        if("${_field}" MATCHES "^usd[.]feature[.](.+)$")
            set(_feature "${CMAKE_MATCH_1}")
            opendcc_deps_dep_feature(_current usd "${_feature}")
            if(NOT "${_current}" STREQUAL "${_value}")
                opendcc_deps_merge_kv(_features "${_features}" "${_feature}=${_value}")
                set(_features_changed ON)
                opendcc_deps_align_note("usd.features.${_feature} ${_current} -> ${_value}")
            endif()
        elseif("${_field}" STREQUAL "usd.version")
            opendcc_deps_align_dependency_version(usd "${_value}")
        elseif("${_field}" STREQUAL "python.version")
            opendcc_deps_align_python("${_value}")
        elseif("${_field}" STREQUAL "tbb.bundled")
            opendcc_deps_key(_tbb_key tbb)
            if(DEPS_DECL_${_tbb_key}_DECLARED)
                opendcc_deps_align_dependency_external(tbb "${prefix}" "${_value}")
            endif()
        elseif("${_field}" MATCHES "^(.+)[.]version$")
            set(_dependency "${CMAKE_MATCH_1}")
            opendcc_deps_key(_dependency_key "${_dependency}")
            if(NOT DEPS_DECL_${_dependency_key}_DECLARED)
                continue()
            endif()
            opendcc_deps_align_dependency_floor("${_dependency}" "${_value}")
        endif()
    endforeach()

    if(_features_changed)
        opendcc_deps_align_remember("DEPS_DECL_USD_FEATURES" "${_features}")
    endif()
endfunction()

# Replay the accumulated assignments in the caller's scope. A macro, not a function: the point is to set the
# variables here, not one scope away.
macro(opendcc_deps_apply_align_assignments)
    get_property(_deps_assignments GLOBAL PROPERTY DEPS_ALIGN_ASSIGNMENTS)
    foreach(_deps_entry IN LISTS _deps_assignments)
        opendcc_deps_unpack(_deps_pair "${_deps_entry}")
        list(GET _deps_pair 0 _deps_variable)
        list(GET _deps_pair 1 _deps_value)
        set(${_deps_variable} "${_deps_value}")
    endforeach()
endmacro()

# Why an external dependency cannot be used: empty when its prefix exists and carries the markers a usable install
# has, otherwise a phrase the fallback note can print.
function(opendcc_deps_external_unavailable_reason out name)
    opendcc_deps_decl(_prefix "${name}" PREFIX)
    if(NOT IS_DIRECTORY "${_prefix}")
        set(${out} "${_prefix} does not exist" PARENT_SCOPE)
        return()
    endif()
    opendcc_deps_key(_key "${name}")
    set(_reason "")
    if(DEFINED DEPS_EXTERNAL_${_key}_MARKERS)
        foreach(_marker IN LISTS DEPS_EXTERNAL_${_key}_MARKERS)
            if("${_reason}" STREQUAL "")
                file(GLOB _matches "${_prefix}/${_marker}")
                if("${_matches}" STREQUAL "")
                    set(_reason "${_prefix} has no ${_marker}")
                endif()
            endif()
        endforeach()
    endif()
    set(${out} "${_reason}" PARENT_SCOPE)
endfunction()

# An external dependency that is not there is provisioned instead of failing: the merged spec goes back to the
# provider this platform declared for it before the overlay, so a source dependency is downloaded and built and a
# brewed one is installed. `ALIGN OFF` says the installation is required, so it never falls back.
function(opendcc_deps_resolve_external_fallbacks)
    foreach(_name IN LISTS DEPS_KNOWN_DEPENDENCIES)
        opendcc_deps_dep_enabled(_enabled "${_name}")
        if(NOT _enabled)
            continue()
        endif()
        opendcc_deps_decl(_provider "${_name}" PROVIDER)
        if(NOT "${_provider}" STREQUAL "external")
            continue()
        endif()
        opendcc_deps_dep_align(_align "${_name}")
        if(NOT _align)
            continue()
        endif()
        opendcc_deps_decl(_prefix "${_name}" PREFIX)
        if("${_prefix}" STREQUAL "")
            # Nothing to look for; validation reports the missing PREFIX.
            continue()
        endif()
        opendcc_deps_external_unavailable_reason(_reason "${_name}")
        if("${_reason}" STREQUAL "")
            continue()
        endif()
        opendcc_deps_base_provider(_base "${_name}")
        if("${_base}" STREQUAL "" OR "${_base}" STREQUAL "external" OR "${_base}" STREQUAL "manual")
            string(CONCAT _problem "external ${_name} is not available (${_reason}) and this platform provisions "
                                   "it with provider \"${_base}\", so there is nothing to fall back to. Point "
                                   "PREFIX at a usable installation, or declare a provider for ${_name} in the "
                                   "overlay.")
            opendcc_deps_die("${_problem}")
        endif()
        opendcc_deps_key(_key "${_name}")
        opendcc_deps_align_remember("DEPS_DECL_${_key}_PROVIDER" "${_base}")
        opendcc_deps_align_remember("DEPS_DECL_${_key}_PREFIX" "")
        opendcc_deps_align_remember("DEPS_DECL_${_key}_ALIGN" "")
        opendcc_deps_align_note("${_name}: ${_reason}; provisioning it with provider ${_base} instead")
    endforeach()
endfunction()

# Rewrite the merged spec from every enabled external dependency that aligns, recording the changes in the global
# properties. Called before validation, so the spec the driver reports and the cache it writes are the final one.
function(opendcc_deps_align_external_specs)
    foreach(_name IN LISTS DEPS_KNOWN_DEPENDENCIES)
        opendcc_deps_dep_enabled(_enabled "${_name}")
        if(NOT _enabled)
            continue()
        endif()
        opendcc_deps_decl(_provider "${_name}" PROVIDER)
        if(NOT "${_provider}" STREQUAL "external")
            continue()
        endif()
        opendcc_deps_dep_align(_align "${_name}")
        if(NOT _align)
            continue()
        endif()
        if(NOT COMMAND opendcc_deps_external_discover_${_name})
            continue()
        endif()
        opendcc_deps_decl(_prefix "${_name}" PREFIX)
        if("${_prefix}" STREQUAL "")
            # Nothing to align against; validation reports the missing PREFIX.
            continue()
        endif()
        opendcc_deps_external_prefix(_prefix "${_name}")
        if(NOT IS_DIRECTORY "${_prefix}")
            opendcc_deps_die("external ${_name} at ${_prefix} does not exist; fix PREFIX or provision that "
                             "dependency")
        endif()
        cmake_language(CALL opendcc_deps_external_discover_${_name} _values _problems "${_prefix}")
        if(NOT "${_problems}" STREQUAL "")
            set(_text "external ${_name} at ${_prefix} cannot be aligned:")
            foreach(_problem IN LISTS _problems)
                string(APPEND _text "\n  ${_problem}")
            endforeach()
            opendcc_deps_die("${_text}")
        endif()
        opendcc_deps_align_values("${_name}" _values "${_prefix}")
    endforeach()
endfunction()

# The single entry point the driver calls: fall back for what is not there, then align what is. Both phases record
# into the same accumulator, and the result is applied to the spec scope once, at the end, so the second phase sees
# the provider the first one chose.
function(opendcc_deps_prepare_external_specs)
    set_property(GLOBAL PROPERTY DEPS_ALIGN_ASSIGNMENTS "")
    set_property(GLOBAL PROPERTY DEPS_ALIGN_NOTES "")
    opendcc_deps_resolve_external_fallbacks()
    opendcc_deps_apply_align_assignments()
    opendcc_deps_align_external_specs()
    opendcc_deps_apply_align_assignments()

    get_property(_assignments GLOBAL PROPERTY DEPS_ALIGN_ASSIGNMENTS)
    foreach(_entry IN LISTS _assignments)
        opendcc_deps_unpack(_pair "${_entry}")
        list(GET _pair 0 _variable)
        list(GET _pair 1 _value)
        set(${_variable} "${_value}" PARENT_SCOPE)
    endforeach()
endfunction()

# What alignment changed. Emitted without a mode, like the driver header, because message(STATUS) writes to stdout in
# script mode and `--print-config` promises stdout is nothing but JSON.
function(opendcc_deps_report_alignment)
    get_property(_notes GLOBAL PROPERTY DEPS_ALIGN_NOTES)
    if("${_notes}" STREQUAL "")
        return()
    endif()
    message("external dependencies:")
    foreach(_note IN LISTS _notes)
        message("  ${_note}")
    endforeach()
    message("")
endfunction()
