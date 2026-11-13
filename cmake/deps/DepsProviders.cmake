# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# Providers: how an enabled dependency reaches the prefix. opendcc_deps_provision() dispatches on the spec's
# provider field to opendcc_deps_provider_<provider>, so adding a platform means adding a spec, possibly a provider
# function here, and its name in DEPS_PROVIDERS — the driver itself does not change.

# `brew --prefix <formula>`, or empty when the formula is not installed.
function(opendcc_deps_brew_prefix out formula)
    execute_process(
        COMMAND brew --prefix "${formula}"
        OUTPUT_VARIABLE _path
        ERROR_QUIET
        RESULT_VARIABLE _code
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT _code EQUAL 0 OR "${_path}" STREQUAL "" OR NOT EXISTS "${_path}")
        set(${out} "" PARENT_SCOPE)
        return()
    endif()
    set(${out} "${_path}" PARENT_SCOPE)
endfunction()

# The keg path is a symlink into the Cellar: <homebrew>/Cellar/<formula>/<version>.
function(opendcc_deps_brew_version out formula)
    opendcc_deps_brew_prefix(_path "${formula}")
    if("${_path}" STREQUAL "")
        set(${out} "" PARENT_SCOPE)
        return()
    endif()
    get_filename_component(_real "${_path}" REALPATH)
    get_filename_component(_version "${_real}" NAME)
    set(${out} "${_version}" PARENT_SCOPE)
endfunction()

# Install or upgrade the formula until the keg satisfies the spec pin.
function(opendcc_deps_ensure_brew name)
    if(NOT CMAKE_HOST_APPLE)
        opendcc_deps_die("brew provider is macOS-only; add a provider for ${DEPS_PLATFORM_TAG}")
    endif()
    opendcc_deps_decl(_formula "${name}" FORMULA)
    opendcc_deps_decl(_pin "${name}" VERSION)
    opendcc_deps_brew_version(_installed "${_formula}")
    opendcc_deps_version_matches(_matches "${_pin}" "${_installed}")
    if(_matches)
        return()
    endif()

    find_program(DEPS_BREW_EXECUTABLE brew)
    if(NOT DEPS_BREW_EXECUTABLE)
        opendcc_deps_die("brew is required to provision ${name}; install Homebrew first")
    endif()

    set(_output "")
    if("${_installed}" STREQUAL "")
        message(STATUS "  ${name}: installing brew ${_formula}")
        set(_action "install")
        execute_process(
            COMMAND brew install --formula "${_formula}"
            OUTPUT_VARIABLE _output
            ERROR_VARIABLE _output
            RESULT_VARIABLE _code)
    else()
        message(STATUS "  ${name}: upgrading brew ${_formula} (${_installed} -> ${_pin})")
        set(_action "upgrade")
        execute_process(
            COMMAND brew upgrade --formula "${_formula}"
            OUTPUT_VARIABLE _output
            ERROR_VARIABLE _output
            RESULT_VARIABLE _code)
    endif()

    opendcc_deps_brew_version(_after "${_formula}")
    opendcc_deps_version_matches(_matches "${_pin}" "${_after}")
    if(NOT _matches)
        if(NOT _code EQUAL 0)
            string(REPLACE "\n" ";" _lines "${_output}")
            list(SUBLIST _lines -20 -1 _tail)
            string(JOIN "\n" _tail_text ${_tail})
            opendcc_deps_die("brew ${_action} of ${_formula} failed:\n${_tail_text}")
        endif()
        opendcc_deps_drift_message(_message "${name}" "${_after}" "${_pin}" "${DEPS_OVERLAY_FILE}")
        opendcc_deps_die("${_message}; then re-run cmake --preset ${DEPS_PLATFORM_TAG}-deps")
    endif()

    opendcc_deps_decl(_expect "${name}" EXPECT)
    opendcc_deps_satisfies(_satisfied _error "${_expect}" "${_after}")
    if(NOT _satisfied)
        opendcc_deps_warn("${name}: warning: brew ${_formula} is ${_after}, outside the expected range ${_expect}")
    endif()
endfunction()

# A source dependency: extract, patch, configure, build, install, stamp. Up to date when the stamp matches the
# plan and the install markers are present.
function(opendcc_deps_provision_source name forced)
    opendcc_deps_key(_key "${name}")
    if(NOT DEFINED DEPS_RECIPE_${_key}_KIND)
        opendcc_deps_decl(_provider "${name}" PROVIDER)
        opendcc_deps_die("enabled ${_provider} dependency \"${name}\" has no recipe in "
                         "cmake/deps/DepsRecipes.cmake")
    endif()
    opendcc_deps_decl(_version "${name}" VERSION)
    opendcc_deps_decl(_strip "${name}" STRIP)
    opendcc_deps_decl(_url "${name}" URL)
    opendcc_deps_decl(_sha "${name}" SHA256)
    opendcc_deps_recipe_kind(_kind "${name}")
    set(_src "${DEPS_PREFIX}/src/${name}")
    set(_build "${DEPS_PREFIX}/build/${name}")

    opendcc_deps_recipe_plan("${name}" _plan _steps _env _requires)
    opendcc_deps_recipe_digest_from_plan(_digest "${name}" "${_plan}")
    opendcc_deps_read_stamp(_stamp_version _stamp_sha "${name}")
    opendcc_deps_recipe_present(_present "${name}")
    if(NOT forced AND "${_stamp_sha}" STREQUAL "${_digest}" AND _present)
        opendcc_deps_info("${name}: up to date (${_version})")
        return()
    endif()

    foreach(_required IN LISTS _requires)
        opendcc_deps_key(_required_key "${_required}")
        if(DEFINED DEPS_RECIPE_${_required_key}_KIND)
            opendcc_deps_recipe_present(_required_present "${_required}")
            if(NOT _required_present)
                opendcc_deps_die("${name} requires \"${_required}\", which is not provisioned yet")
            endif()
        endif()
    endforeach()

    # A rebuild must not reuse objects produced from the previous source tree: the archive is re-extracted and the
    # patches reapplied, and a stale build directory silently keeps the old flags and files.
    if(IS_DIRECTORY "${_build}")
        opendcc_deps_info("removing the previous build directory")
        file(REMOVE_RECURSE "${_build}")
    endif()

    opendcc_deps_download(
        NAME
        "${name}"
        URL
        "${_url}"
        SHA256
        "${_sha}"
        OUT_PATH
        _archive
        OUT_SHA
        _archive_sha)
    get_filename_component(_archive_name "${_archive}" NAME)
    message(STATUS "  ${name}: extracting ${_archive_name}")
    opendcc_deps_extract("${_archive}" "${_src}" "${_strip}")
    opendcc_deps_apply_patches("${name}" "${DEPS_RECIPE_${_key}_PATCHES}" "${_src}")
    if(COMMAND opendcc_deps_recipe_verify_${name})
        cmake_language(CALL opendcc_deps_recipe_verify_${name} "${_src}")
    endif()

    if("${_steps}" STREQUAL "")
        opendcc_deps_info("no build step (${_kind})")
    endif()
    opendcc_deps_run_steps("${name}" _steps _env)

    opendcc_deps_recipe_present(_present "${name}")
    if(NOT _present)
        opendcc_deps_die("${name} built, but its expected files are missing from ${DEPS_PREFIX}")
    endif()
    opendcc_deps_write_stamp("${name}" "${_version}" "${_digest}")
endfunction()

function(opendcc_deps_provider_brew name forced)
    opendcc_deps_ensure_brew("${name}")
endfunction()

function(opendcc_deps_provider_source name forced)
    opendcc_deps_provision_source("${name}" ${forced})
endfunction()

function(opendcc_deps_provider_headers name forced)
    opendcc_deps_provision_source("${name}" ${forced})
endfunction()

function(opendcc_deps_provider_manual name forced)
    opendcc_deps_info("${name}: manual dependency, not provisioned by this driver")
    opendcc_deps_decl(_variables "${name}" CMAKE_VARS)
    set(_entries "${_variables}")
    if(NOT "${_entries}" STREQUAL "")
        list(SORT _entries)
    endif()
    foreach(_entry IN LISTS _entries)
        string(FIND "${_entry}" "=" _split)
        string(SUBSTRING "${_entry}" 0 ${_split} _variable)
        math(EXPR _value_start "${_split}+1")
        string(SUBSTRING "${_entry}" ${_value_start} -1 _value)
        if("${_value}" MATCHES "@MANUAL@")
            opendcc_deps_info("set ${_variable} so find_package(${name}) can locate it")
        endif()
    endforeach()
endfunction()

# Calls opendcc_deps_provider_<provider> for every enabled target. A provider without a function here is a hard
# error, so a spec that names one the driver cannot serve fails before anything is written.
function(opendcc_deps_provision targets_var forced_var)
    foreach(_name IN LISTS ${targets_var})
        opendcc_deps_dep_enabled(_enabled "${_name}")
        if(NOT _enabled)
            continue()
        endif()
        opendcc_deps_decl(_provider "${_name}" PROVIDER)
        message(STATUS "${_name}:")
        if(NOT COMMAND opendcc_deps_provider_${_provider})
            opendcc_deps_die("${_name}: unsupported provider \"${_provider}\"")
        endif()
        # Copy the forced set before defining a local: ${forced_var} names the caller's variable and a same-named
        # local here would shadow it.
        set(_forced_names "${${forced_var}}")
        set(_is_forced OFF)
        if("${_name}" IN_LIST _forced_names)
            set(_is_forced ON)
        endif()
        cmake_language(CALL opendcc_deps_provider_${_provider} "${_name}" ${_is_forced})
    endforeach()
endfunction()
