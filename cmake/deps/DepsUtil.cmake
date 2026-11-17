# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# Shared helpers for the dependency-prefix driver. Everything here is configure-time code: no targets, no rules,
# no cache entries other than the ones the caller declares.

# The repository root, independent of how this directory was reached.
get_filename_component(DEPS_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)

# Separator for packed lists (a step's label plus its argv, an environment entry). CMake lists cannot hold a
# literal ';' without escaping, and step arguments do contain them: -DCMAKE_PREFIX_PATH=a;b. ASCII 31 is the unit
# separator and cannot appear in a path, a version or a flag.
string(ASCII 31 DEPS_US)

# CMake passes "a " "b" as two arguments, and message()/file(WRITE)/set() treat them as separate values. Anything
# that has to end up as one value (a message, a JSON document, a file body) either uses string(CONCAT) or the
# fragments of these three, which join their own arguments exactly as written (ARGVn keeps each one unsplit).
function(opendcc_deps_die)
    set(_text "${ARGV0}")
    math(EXPR _last "${ARGC}-1")
    if(_last GREATER 0)
        foreach(_index RANGE 1 ${_last})
            string(APPEND _text "${ARGV${_index}}")
        endforeach()
    endif()
    message(FATAL_ERROR "${_text}")
endfunction()

function(opendcc_deps_info)
    set(_text "${ARGV0}")
    math(EXPR _last "${ARGC}-1")
    if(_last GREATER 0)
        foreach(_index RANGE 1 ${_last})
            string(APPEND _text "${ARGV${_index}}")
        endforeach()
    endif()
    message(STATUS "  ${_text}")
endfunction()

function(opendcc_deps_warn)
    set(_text "${ARGV0}")
    math(EXPR _last "${ARGC}-1")
    if(_last GREATER 0)
        foreach(_index RANGE 1 ${_last})
            string(APPEND _text "${ARGV${_index}}")
        endforeach()
    endif()
    message(WARNING "  ${_text}")
endfunction()

# Run a program, returning its combined output and exit code. A missing binary is reported through the exit code
# ("no such file or directory") rather than aborting, because callers probe for tools that may be absent.
function(opendcc_deps_run out_output out_code)
    execute_process(
        COMMAND ${ARGN}
        OUTPUT_VARIABLE _stdout
        ERROR_VARIABLE _stderr
        RESULT_VARIABLE _code
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE)
    set(${out_output} "${_stdout}${_stderr}" PARENT_SCOPE)
    set(${out_code} "${_code}" PARENT_SCOPE)
endfunction()

# Append values to a list variable without splitting them on ';'. Elements are stored escaped, so reading them
# back with foreach()/list(GET) yields the original string; pass such lists to functions by variable name, never
# by expansion.
function(opendcc_deps_list_append listvar)
    set(_acc "${${listvar}}")
    math(EXPR _last "${ARGC}-1")
    foreach(_i RANGE 1 ${_last})
        set(_value "${ARGV${_i}}")
        string(REPLACE ";" "\\;" _value "${_value}")
        if("${_acc}" STREQUAL "")
            set(_acc "${_value}")
        else()
            string(APPEND _acc ";${_value}")
        endif()
    endforeach()
    set(${listvar} "${_acc}" PARENT_SCOPE)
endfunction()

# Split a packed (DEPS_US separated) string into a list variable.
function(opendcc_deps_unpack out packed)
    if("${packed}" STREQUAL "")
        set(${out} "" PARENT_SCOPE)
        return()
    endif()
    set(_rest "${packed}")
    set(_items "")
    while(TRUE)
        string(FIND "${_rest}" "${DEPS_US}" _pos)
        if(_pos LESS 0)
            opendcc_deps_list_append(_items "${_rest}")
            break()
        endif()
        string(SUBSTRING "${_rest}" 0 ${_pos} _item)
        opendcc_deps_list_append(_items "${_item}")
        math(EXPR _next "${_pos}+1")
        string(SUBSTRING "${_rest}" ${_next} -1 _rest)
    endwhile()
    set(${out} "${_items}" PARENT_SCOPE)
endfunction()

# Pack one step: the label followed by its argv, separated by DEPS_US. The arguments come from a list *variable*
# because an argument that itself contains ';' (-DCMAKE_PREFIX_PATH=a;b) cannot be forwarded through a function
# call: expanding a list into arguments resolves the escapes and splits it.
function(opendcc_deps_pack_step out label arguments_var)
    set(_packed "${label}")
    foreach(_argument IN LISTS ${arguments_var})
        string(APPEND _packed "${DEPS_US}${_argument}")
    endforeach()
    set(${out} "${_packed}" PARENT_SCOPE)
endfunction()

macro(opendcc_deps_unpack_step out_label out_argv packed)
    string(FIND "${packed}" "${DEPS_US}" _unpack_step_position)
    if(_unpack_step_position LESS 0)
        opendcc_deps_die("internal error: step has no arguments")
    endif()
    string(SUBSTRING "${packed}" 0 ${_unpack_step_position} ${out_label})
    math(EXPR _unpack_step_next "${_unpack_step_position}+1")
    string(SUBSTRING "${packed}" ${_unpack_step_next} -1 _unpack_step_rest)
    opendcc_deps_unpack(${out_argv} "${_unpack_step_rest}")
endmacro()

# Path relative to the repository root when it lives under it, unchanged otherwise (mirrors spec.py:rel()).
function(opendcc_deps_rel out path)
    if(NOT path)
        set(${out} "" PARENT_SCOPE)
        return()
    endif()
    get_filename_component(_abs "${path}" ABSOLUTE BASE_DIR "${DEPS_REPO_ROOT}")
    set(_root "${DEPS_REPO_ROOT}/")
    string(FIND "${_abs}" "${_root}" _index)
    if(_index EQUAL 0)
        string(LENGTH "${_root}" _length)
        string(SUBSTRING "${_abs}" ${_length} -1 _relative)
        set(${out} "${_relative}" PARENT_SCOPE)
    else()
        set(${out} "${_abs}" PARENT_SCOPE)
    endif()
endfunction()

# "name" written the way the DEPS_DECL_<KEY>_<FIELD> variables spell it.
function(opendcc_deps_key out name)
    string(TOUPPER "${name}" _key)
    string(REPLACE "-" "_" _key "${_key}")
    set(${out} "${_key}" PARENT_SCOPE)
endfunction()

# Quote a value for inclusion in a generated CMake file.
function(opendcc_deps_quote out value)
    string(REPLACE "\\" "\\\\" _value "${value}")
    string(REPLACE "\"" "\\\"" _value "${_value}")
    set(${out} "\"${_value}\"" PARENT_SCOPE)
endfunction()

function(opendcc_deps_sha256_file out path)
    file(SHA256 "${path}" _digest)
    set(${out} "${_digest}" PARENT_SCOPE)
endfunction()

function(opendcc_deps_sha256_text out text)
    string(SHA256 _digest "${text}")
    set(${out} "${_digest}" PARENT_SCOPE)
endfunction()

# The ON values the driver accepts from the environment (OPENDCC_DEPS_UPDATE_LOCK).
function(opendcc_deps_is_true out value)
    string(TOUPPER "${value}" _upper)
    if("${_upper}" STREQUAL "1"
       OR "${_upper}" STREQUAL "ON"
       OR "${_upper}" STREQUAL "YES"
       OR "${_upper}" STREQUAL "TRUE")
        set(${out} ON PARENT_SCOPE)
    else()
        set(${out} OFF PARENT_SCOPE)
    endif()
endfunction()

# The last <count> lines of a file, for build failures.
function(opendcc_deps_tail out path count)
    if(NOT EXISTS "${path}")
        set(${out} "" PARENT_SCOPE)
        return()
    endif()
    file(STRINGS "${path}" _lines)
    list(LENGTH _lines _length)
    if(_length GREATER count)
        math(EXPR _start "${_length}-${count}")
    else()
        set(_start 0)
    endif()
    list(SUBLIST _lines ${_start} -1 _tail)
    string(JOIN "\n" _text ${_tail})
    set(${out} "${_text}" PARENT_SCOPE)
endfunction()

# ----------------------------------------------------------------------------------------------------------
# versions (port of spec.py's _split_version/_cmp/version_matches/satisfies)

# Numeric components of a version string, as a list: "v2.6.0" -> 2;6;0.
function(opendcc_deps_version_split out value)
    string(REGEX MATCHALL "[0-9]+" _parts "${value}")
    set(${out} "${_parts}" PARENT_SCOPE)
endfunction()

# Sign of a - b over padded numeric component lists.
function(opendcc_deps_version_cmp out a b)
    list(LENGTH a _length_a)
    list(LENGTH b _length_b)
    if(_length_a GREATER _length_b)
        set(_count ${_length_a})
    else()
        set(_count ${_length_b})
    endif()
    set(_result 0)
    if(_count GREATER 0)
        math(EXPR _last "${_count}-1")
        foreach(_index RANGE 0 ${_last})
            set(_left 0)
            set(_right 0)
            if(_index LESS _length_a)
                list(GET a ${_index} _left)
            endif()
            if(_index LESS _length_b)
                list(GET b ${_index} _right)
            endif()
            if(_left GREATER _right)
                set(_result 1)
                break()
            elseif(_left LESS _right)
                set(_result -1)
                break()
            endif()
        endforeach()
    endif()
    set(${out} ${_result} PARENT_SCOPE)
endfunction()

# True when <installed> satisfies the <pin>. The pin's precision governs, so "4.3.5" accepts 4.3.5_2 and "3.2.2"
# accepts 3.2.2.0_1; Homebrew revisions carry no meaning. "any"/empty accept anything.
function(opendcc_deps_version_matches out pin installed)
    if("${pin}" STREQUAL "" OR "${pin}" STREQUAL "any")
        set(${out} ON PARENT_SCOPE)
        return()
    endif()
    if("${installed}" STREQUAL "")
        set(${out} OFF PARENT_SCOPE)
        return()
    endif()
    set(_base "${installed}")
    string(FIND "${_base}" "_" _underscore)
    if(_underscore GREATER -1)
        string(SUBSTRING "${_base}" 0 ${_underscore} _base)
    endif()
    opendcc_deps_version_split(_wanted "${pin}")
    opendcc_deps_version_split(_have "${_base}")
    list(LENGTH _wanted _wanted_length)
    if(_wanted_length EQUAL 0)
        set(${out} ON PARENT_SCOPE)
        return()
    endif()
    list(LENGTH _have _have_length)
    if(_have_length LESS _wanted_length)
        set(${out} OFF PARENT_SCOPE)
        return()
    endif()
    math(EXPR _last "${_wanted_length}-1")
    foreach(_index RANGE 0 ${_last})
        list(GET _wanted ${_index} _want)
        list(GET _have ${_index} _has)
        if(NOT _want EQUAL _has)
            set(${out} OFF PARENT_SCOPE)
            return()
        endif()
    endforeach()
    set(${out} ON PARENT_SCOPE)
endfunction()

# True when <installed> is at least <floor>. A version pxrConfig records for a library it links is a minimum
# (`find_dependency(TBB 2020.3 CONFIG)`), unlike the exact pins the spec uses for kegs.
function(opendcc_deps_version_at_least out installed floor)
    if("${floor}" STREQUAL "" OR "${floor}" STREQUAL "any")
        set(${out} ON PARENT_SCOPE)
        return()
    endif()
    if("${installed}" STREQUAL "" OR "${installed}" STREQUAL "any")
        set(${out} OFF PARENT_SCOPE)
        return()
    endif()
    opendcc_deps_version_split(_installed_parts "${installed}")
    opendcc_deps_version_split(_floor_parts "${floor}")
    opendcc_deps_version_cmp(_order "${_installed_parts}" "${_floor_parts}")
    if(_order LESS 0)
        set(${out} OFF PARENT_SCOPE)
    else()
        set(${out} ON PARENT_SCOPE)
    endif()
endfunction()

# Range check against an "expect" field; reports the unsupported-range problem instead of dying so the caller can
# collect it.
function(opendcc_deps_satisfies out_ok out_error expect version)
    set(${out_ok} ON PARENT_SCOPE)
    set(${out_error} "" PARENT_SCOPE)
    if("${expect}" STREQUAL ""
       OR "${expect}" STREQUAL "any"
       OR "${version}" STREQUAL ""
       OR "${version}" STREQUAL "any")
        return()
    endif()
    string(STRIP "${expect}" _text)
    opendcc_deps_version_split(_have "${version}")
    if("${_text}" MATCHES "^>=")
        string(SUBSTRING "${_text}" 2 -1 _floor)
        string(STRIP "${_floor}" _floor)
        opendcc_deps_version_split(_floor_parts "${_floor}")
        opendcc_deps_version_cmp(_sign "${_have}" "${_floor_parts}")
        if(_sign LESS 0)
            set(${out_ok} OFF PARENT_SCOPE)
        endif()
        return()
    endif()
    if("${_text}" MATCHES "^==")
        string(SUBSTRING "${_text}" 2 -1 _exact)
        string(STRIP "${_exact}" _exact)
        opendcc_deps_version_matches(_matches "${_exact}" "${version}")
        set(${out_ok} ${_matches} PARENT_SCOPE)
        return()
    endif()
    set(${out_ok} OFF PARENT_SCOPE)
    set(${out_error} "unsupported \"expect\" range '${expect}'" PARENT_SCOPE)
endfunction()

function(opendcc_deps_drift_message out name installed pin overlay_file)
    if("${installed}" STREQUAL "")
        set(_shown "not installed")
        set(_suggested "${pin}")
    else()
        set(_shown "${installed}")
        set(_suggested "${installed}")
    endif()
    opendcc_deps_rel(_where "${overlay_file}")
    set(${out}
        "${name} is ${_shown}, spec expects ${pin}; set opendcc_deps_spec_dependency(${name} VERSION ${_suggested}) "
        "in ${_where}" PARENT_SCOPE)
endfunction()
