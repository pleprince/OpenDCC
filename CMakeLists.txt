cmake_minimum_required(VERSION 3.18)

# CMake 4 defaults CMP0167 to NEW, which makes find_package(Boost) ignore cmake/modules/FindBoost.cmake and use the
# upstream config instead. The build relies on the module's variables (Boost_LIBRARY_DIR_RELEASE, Boost_NO_BOOST_CMAKE),
# so keep the module.
if(POLICY CMP0167)
    cmake_policy(SET CMP0167 OLD)
endif()

if(CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_CXX_FLAGS_HYBRID
        "${CMAKE_CXX_FLAGS_RELWITHDEBINFO} /Od /Ob0"
        CACHE STRING "FLAGS" FORCE)
    set(CMAKE_C_FLAGS_HYBRID
        "${CMAKE_C_FLAGS_RELWITHDEBINFO} /Od /Ob0"
        CACHE STRING "FLAGS" FORCE)
    set(CMAKE_EXE_LINKER_FLAGS_HYBRID
        "${CMAKE_EXE_LINKER_FLAGS_RELWITHDEBINFO}"
        CACHE STRING "FLAGS" FORCE)
    set(CMAKE_SHARED_LINKER_FLAGS_HYBRID
        "${CMAKE_SHARED_LINKER_FLAGS_RELWITHDEBINFO}"
        CACHE STRING "CXX FLAGS" FORCE)
    set(CMAKE_CONFIGURATION_TYPES
        "Release;RelWithDebInfo;Debug;Hybrid"
        CACHE STRING "Configurations" FORCE)
endif()

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release")
endif()

set_property(GLOBAL PROPERTY USE_FOLDERS ON)

project(OpenDCC VERSION 0.4.0.0)

# The dependency prefix is provisioned by tools/deps/bootstrap.py from deps/<platform>.json, which is the only place
# versions and features are declared. That driver writes deps.generated.cmake; nothing else is consumed here. Linux and
# Windows never set OPENDCC_DEPS_DIR and are unaffected.
if(DEFINED ENV{OPENDCC_DEPS_DIR})
    if(NOT EXISTS "$ENV{OPENDCC_DEPS_DIR}/deps.generated.cmake")
        message(FATAL_ERROR "Dependency prefix not provisioned. Run:\n"
                            "  python3 tools/deps/bootstrap.py --prefix $ENV{OPENDCC_DEPS_DIR}")
    endif()
    include("$ENV{OPENDCC_DEPS_DIR}/deps.generated.cmake")
    message(STATUS "Using dependency prefix: ${DCC_DEPS_PREFIX}")

    # A preset may point at an overlay the user has not created yet, so only a real disagreement is an error: the
    # environment names a different overlay that exists, or this prefix was provisioned from one that exists.
    if(DEFINED ENV{OPENDCC_DEPS_CONFIG}
       AND NOT "$ENV{OPENDCC_DEPS_CONFIG}" STREQUAL "${DCC_DEPS_OVERLAY_FILE}"
       AND (EXISTS "$ENV{OPENDCC_DEPS_CONFIG}" OR (DCC_DEPS_OVERLAY_FILE AND EXISTS "${DCC_DEPS_OVERLAY_FILE}")))
        if(DCC_DEPS_OVERLAY_FILE)
            set(_deps_provisioned_overlay "${DCC_DEPS_OVERLAY_FILE}")
        else()
            set(_deps_provisioned_overlay "(no overlay)")
        endif()
        message(FATAL_ERROR "OPENDCC_DEPS_CONFIG is $ENV{OPENDCC_DEPS_CONFIG} but the prefix was provisioned "
                            "from ${_deps_provisioned_overlay}. Re-run tools/deps/bootstrap.py.")
    endif()

    # The cache is only valid for the spec it was generated from; bootstrap.py hashes the same fields.
    set(_deps_token "")
    foreach(_deps_spec_file "${DCC_DEPS_SPEC_FILE}" "${DCC_DEPS_OVERLAY_FILE}")
        if(_deps_spec_file AND EXISTS "${_deps_spec_file}")
            file(TIMESTAMP "${_deps_spec_file}" _deps_spec_time "%Y%m%d%H%M%S" UTC)
            file(SIZE "${_deps_spec_file}" _deps_spec_size)
            string(APPEND _deps_token "${_deps_spec_file}|${_deps_spec_time}|${_deps_spec_size};")
        endif()
    endforeach()
    string(SHA256 _deps_token "${_deps_token}")
    if(NOT _deps_token STREQUAL "${DCC_DEPS_SPEC_TOKEN}")
        message(FATAL_ERROR "Dependency spec changed since provisioning. Run:\n" "  python3 tools/deps/bootstrap.py")
    endif()
endif()

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CMAKE_SOURCE_DIR}/cmake/defaults ${CMAKE_SOURCE_DIR}/cmake/modules
                      ${CMAKE_SOURCE_DIR}/cmake/macros)

include_directories(${PROJECT_SOURCE_DIR}/src/lib)

include(Version)
include(MakeTargets)
include(MakeFolder)
include(CXXDefaults)
include(Platform)
include(Options)
include(Packages)
include(VsStudioUtils)
include(InstallCmakeConfig)
include(UpdateTranslations)

if(DCC_BUILD_TESTS)
    include(MakeTests)
    enable_testing()
endif()

add_subdirectory(src)
if(DCC_BUILD_TESTS)
    add_subdirectory(tests)
endif()

include(InstallDependencies)
include(InstallStartupConfigs)
