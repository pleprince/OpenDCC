# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# The platform seam. This is the only file in the driver with host conditionals: the spec tag, the toolchain probe
# and the interpreter layout all live here, so a new platform adds a spec plus provider functions and touches
# nothing else.

# Machine name of the host. CMAKE_HOST_SYSTEM_PROCESSOR is only set once a language has been enabled, so script
# mode (-P, used for --print-config piping) falls back to uname.
function(opendcc_deps_host_machine out)
    set(_machine "${CMAKE_HOST_SYSTEM_PROCESSOR}")
    if("${_machine}" STREQUAL "" AND NOT CMAKE_HOST_WIN32)
        execute_process(
            COMMAND uname -m
            OUTPUT_VARIABLE _machine
            ERROR_QUIET
            RESULT_VARIABLE _code
            OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(NOT _code EQUAL 0)
            set(_machine "")
        endif()
    endif()
    set(${out} "${_machine}" PARENT_SCOPE)
endfunction()

# Spec tag for this host. A spec names the platform it provisions, so the tag comes from the host, not from
# CMAKE_OSX_ARCHITECTURES: cross-provisioning a dependency prefix is not supported.
function(opendcc_deps_platform_tag out)
    opendcc_deps_host_machine(_machine)
    string(TOLOWER "${CMAKE_HOST_SYSTEM_NAME}" _system)
    set(_tag "")
    if(CMAKE_HOST_APPLE)
        if("${_machine}" STREQUAL "arm64")
            set(_tag "macos-arm64")
        elseif("${_machine}" STREQUAL "x86_64")
            set(_tag "macos-x64")
        endif()
    elseif(CMAKE_HOST_WIN32)
        if("${_machine}" STREQUAL "AMD64" OR "${_machine}" STREQUAL "x86_64")
            set(_tag "windows-x64")
        elseif("${_machine}" STREQUAL "arm64")
            set(_tag "windows-arm64")
        endif()
    elseif("${_system}" STREQUAL "linux")
        if("${_machine}" STREQUAL "x86_64")
            set(_tag "linux-x64")
        elseif("${_machine}" STREQUAL "aarch64" OR "${_machine}" STREQUAL "arm64")
            set(_tag "linux-arm64")
        endif()
    endif()
    if("${_tag}" STREQUAL "")
        string(TOLOWER "${_machine}" _machine_name)
        opendcc_deps_die("no dependency spec for ${_system}-${_machine_name} (expected "
                         "deps/${_system}-${_machine_name}.cmake); set OPENDCC_DEPS_SPEC to point at one")
    endif()
    set(${out} "${_tag}" PARENT_SCOPE)
endfunction()

# Target architecture handed to every source build, and the parallel job count. Both come from the environment so
# a provisioned prefix records nothing machine-specific.
function(opendcc_deps_platform_defaults)
    if(CMAKE_OSX_ARCHITECTURES)
        set(DEPS_ARCH "${CMAKE_OSX_ARCHITECTURES}")
    elseif(NOT "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "")
        set(DEPS_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
    else()
        opendcc_deps_host_machine(DEPS_ARCH)
    endif()
    if(CMAKE_HOST_WIN32)
        set(DEPS_PATH_SEPARATOR ";")
    else()
        set(DEPS_PATH_SEPARATOR ":")
    endif()
    if(DEFINED ENV{OPENDCC_DEPS_JOBS} AND NOT "$ENV{OPENDCC_DEPS_JOBS}" STREQUAL "")
        set(DEPS_JOBS "$ENV{OPENDCC_DEPS_JOBS}")
    else()
        include(ProcessorCount)
        ProcessorCount(DEPS_JOBS)
        if(DEPS_JOBS LESS 1)
            set(DEPS_JOBS 1)
        endif()
    endif()
    set(DEPS_ARCH "${DEPS_ARCH}" PARENT_SCOPE)
    set(DEPS_JOBS "${DEPS_JOBS}" PARENT_SCOPE)
    set(DEPS_PATH_SEPARATOR "${DEPS_PATH_SEPARATOR}" PARENT_SCOPE)
endfunction()

function(opendcc_deps_platform_check_toolchain)
    if(NOT CMAKE_HOST_APPLE)
        return()
    endif()
    opendcc_deps_run(_selected _code xcode-select -p)
    if(NOT _code EQUAL 0)
        opendcc_deps_die("Xcode command line tools are required: run `xcode-select --install`")
    endif()
    opendcc_deps_run(_version _code xcodebuild -version)
    if("${_version}" MATCHES "CommandLineTools")
        opendcc_deps_warn("only the Command Line Tools are selected; a full Xcode is required for some SDKs")
    endif()
endfunction()

# Architecture flags every source build gets, on top of the generic arguments.
function(opendcc_deps_platform_cmake_args out)
    set(_args "")
    if(CMAKE_HOST_APPLE)
        opendcc_deps_list_append(_args "-DCMAKE_OSX_ARCHITECTURES=${DEPS_ARCH}")
    endif()
    set(${out} "${_args}" PARENT_SCOPE)
endfunction()

function(opendcc_deps_platform_venv_python out prefix)
    if(CMAKE_HOST_WIN32)
        set(${out} "${prefix}/venv/Scripts/python.exe" PARENT_SCOPE)
    else()
        set(${out} "${prefix}/venv/bin/python3" PARENT_SCOPE)
    endif()
endfunction()

function(opendcc_deps_platform_python_site_packages out prefix major minor)
    if(CMAKE_HOST_WIN32)
        set(${out} "${prefix}/venv/Lib/site-packages" PARENT_SCOPE)
    else()
        set(${out} "${prefix}/venv/lib/python${major}.${minor}/site-packages" PARENT_SCOPE)
    endif()
endfunction()

# The SDK sysroot; Homebrew's libclang only finds SDK headers when told.
function(opendcc_deps_platform_sdkroot out)
    set(_sdkroot "")
    if(CMAKE_HOST_APPLE)
        opendcc_deps_run(_path _code xcrun --show-sdk-path)
        if(_code EQUAL 0)
            set(_sdkroot "${_path}")
        endif()
    endif()
    set(${out} "${_sdkroot}" PARENT_SCOPE)
endfunction()
