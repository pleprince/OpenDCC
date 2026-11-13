# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# Builds the py-setpythonhome(<install prefix>) archive: a zip of the pinned interpreter's standard library, so the
# embedded interpreter finds encodings/ and friends without a system python. Invoked as a script:
#
#   cmake -DPYTHON_EXECUTABLE=<interpreter> -DOUTPUT_DIR=<dir> -P make_python_stdlib_zip.cmake
#
# Two differences from a hand-written zip matter for the embedded interpreter: the interpreter is queried for
# base_prefix (a venv's own prefix holds no standard library) and site-packages/lib-dynload are left out (the
# install tree carries those itself).

foreach(_required PYTHON_EXECUTABLE OUTPUT_DIR)
    if(NOT DEFINED ${_required})
        message(FATAL_ERROR "make_python_stdlib_zip.cmake requires -D${_required}=...")
    endif()
endforeach()

if(NOT EXISTS "${PYTHON_EXECUTABLE}")
    message(FATAL_ERROR "interpreter not found: ${PYTHON_EXECUTABLE}")
endif()

execute_process(
    COMMAND "${PYTHON_EXECUTABLE}" -c "import sys; print(getattr(sys, 'base_prefix', sys.prefix))"
    OUTPUT_VARIABLE _base_prefix
    ERROR_VARIABLE _error
    RESULT_VARIABLE _code
    OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _code EQUAL 0 OR _base_prefix STREQUAL "")
    message(FATAL_ERROR "cannot query base_prefix from ${PYTHON_EXECUTABLE}: ${_error}")
endif()

execute_process(
    COMMAND "${PYTHON_EXECUTABLE}" -c "import sys; print('%d.%d' % sys.version_info[:2])"
    OUTPUT_VARIABLE _version
    ERROR_VARIABLE _error
    RESULT_VARIABLE _code
    OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _code EQUAL 0 OR NOT _version MATCHES "^[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR "cannot query the version from ${PYTHON_EXECUTABLE}: ${_error}")
endif()
string(REPLACE "." ";" _version_parts "${_version}")
list(GET _version_parts 0 _major)
list(GET _version_parts 1 _minor)

if(CMAKE_HOST_WIN32)
    set(_library_path "${_base_prefix}/lib")
else()
    set(_library_path "${_base_prefix}/lib/python${_major}.${_minor}")
endif()
if(NOT IS_DIRECTORY "${_library_path}")
    message(FATAL_ERROR "no standard library at ${_library_path}")
endif()

file(GLOB_RECURSE _candidates RELATIVE "${_library_path}" "${_library_path}/*.py")
set(_sources "")
foreach(_source IN LISTS _candidates)
    if(_source MATCHES "^(site-packages|lib-dynload)/")
        continue()
    endif()
    list(APPEND _sources "${_source}")
endforeach()
if(NOT _sources)
    message(FATAL_ERROR "no .py files under ${_library_path}")
endif()

set(_archive "${OUTPUT_DIR}/python${_major}${_minor}.zip")
file(MAKE_DIRECTORY "${OUTPUT_DIR}")
file(REMOVE "${_archive}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar cf "${_archive}" --format=zip -- ${_sources}
    WORKING_DIRECTORY "${_library_path}"
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    RESULT_VARIABLE _code)
if(NOT _code EQUAL 0)
    message(FATAL_ERROR "cannot write ${_archive}: ${_output}${_error}")
endif()
