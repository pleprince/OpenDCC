# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# Dependency-prefix driver. Reached only through the root CMakeLists' DEPS_MODE branch: it provisions (or inspects)
# the prefix declared by deps/<platform>.cmake and writes the deps.generated.cmake the application build consumes.
# Nothing here adds a target, so the driver configures in its own build directory (build/deps, via the
# <platform>-deps presets) instead of interfering with the application build tree.

set(DEPS_MODES provision check list print-config)
if(NOT "${DEPS_MODE}" IN_LIST DEPS_MODES)
    message(FATAL_ERROR "DEPS_MODE must be one of ${DEPS_MODES}, found \"${DEPS_MODE}\"")
endif()

# CMP0174 (CMake 3.31): a keyword followed by an empty value defines it as empty instead of unsetting it. The
# spec passes empty SHA256/VERSION values for unpinned artifacts, so the driver wants the new behaviour.
if(POLICY CMP0174)
    cmake_policy(SET CMP0174 NEW)
endif()

set(DEPS_PATCH_TOOL
    "patch"
    CACHE FILEPATH "patch(1) used to apply tools/deps/patches to extracted dependency sources")

include("${CMAKE_CURRENT_LIST_DIR}/DepsUtil.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/DepsSpec.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/DepsPlatform.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/DepsGenerate.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/DepsRecipes.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/DepsAlign.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/DepsProviders.cmake")

opendcc_deps_platform_tag(DEPS_PLATFORM_TAG)
opendcc_deps_platform_defaults()

# Spec: OPENDCC_DEPS_SPEC when set, otherwise deps/<platform>.cmake.
if(DEFINED ENV{OPENDCC_DEPS_SPEC} AND NOT "$ENV{OPENDCC_DEPS_SPEC}" STREQUAL "")
    set(DEPS_SPEC_FILE "$ENV{OPENDCC_DEPS_SPEC}")
else()
    set(DEPS_SPEC_FILE "${DEPS_PLATFORM_TAG}.cmake")
endif()
get_filename_component(DEPS_SPEC_FILE "${DEPS_SPEC_FILE}" ABSOLUTE BASE_DIR "${DEPS_REPO_ROOT}/deps")
if(NOT EXISTS "${DEPS_SPEC_FILE}")
    opendcc_deps_rel(_spec_rel "${DEPS_SPEC_FILE}")
    opendcc_deps_die("no dependency spec at ${_spec_rel}; add it or point OPENDCC_DEPS_SPEC at one")
endif()

# Overlay: gitignored per-machine overrides, included right after the base spec.
if(DEFINED ENV{OPENDCC_DEPS_CONFIG} AND NOT "$ENV{OPENDCC_DEPS_CONFIG}" STREQUAL "")
    set(DEPS_OVERLAY_FILE "$ENV{OPENDCC_DEPS_CONFIG}")
else()
    string(REGEX REPLACE "[.]cmake$" "" _spec_stem "${DEPS_SPEC_FILE}")
    set(DEPS_OVERLAY_FILE "${_spec_stem}.local.cmake")
endif()
get_filename_component(DEPS_OVERLAY_FILE "${DEPS_OVERLAY_FILE}" ABSOLUTE BASE_DIR "${DEPS_REPO_ROOT}")

# Prefix: the same directory the application build points OPENDCC_DEPS_DIR at.
if(DEFINED ENV{OPENDCC_DEPS_DIR} AND NOT "$ENV{OPENDCC_DEPS_DIR}" STREQUAL "")
    set(DEPS_PREFIX "$ENV{OPENDCC_DEPS_DIR}")
else()
    set(DEPS_PREFIX "${DEPS_REPO_ROOT}/install_dir/deps")
endif()
get_filename_component(DEPS_PREFIX "${DEPS_PREFIX}" ABSOLUTE BASE_DIR "${DEPS_REPO_ROOT}")

string(REGEX REPLACE "[.]cmake$" "" _lock_stem "${DEPS_SPEC_FILE}")
set(DEPS_LOCK_FILE "${_lock_stem}.lock.cmake")

opendcc_deps_lock_load("${DEPS_LOCK_FILE}")

opendcc_deps_spec_reset()
include("${DEPS_SPEC_FILE}")
# What this platform provisions each dependency with, before an overlay can point it somewhere else: the fallback for
# an external dependency that turns out to be unavailable.
opendcc_deps_record_base_providers()
if(EXISTS "${DEPS_OVERLAY_FILE}")
    include("${DEPS_OVERLAY_FILE}")
endif()

# An external dependency defines the versions this build must use; adopting them before validation means everything
# below (provisioning, the generated cache, the application build) describes that installation. One that is not
# installed is provisioned with the provider the platform declared for it instead of failing.
opendcc_deps_prepare_external_specs()

opendcc_deps_spec_validate(_spec_problems)
if(NOT "${_spec_problems}" STREQUAL "")
    foreach(_problem IN LISTS _spec_problems)
        message(STATUS "${_problem}")
    endforeach()
    message(FATAL_ERROR "dependency spec is not usable")
endif()

opendcc_deps_main()
