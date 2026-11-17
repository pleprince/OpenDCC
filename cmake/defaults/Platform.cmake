# Copyright Contributors to the OpenDCC project SPDX-License-Identifier: Apache-2.0
#
# Platform-wide compile/link settings. Included from the root list right after CXXDefaults, before any target is
# declared, so the rpath and definition settings reach every target.

if(APPLE)
    # Homebrew dylibs live outside the install tree and dependencies in our own prefix are addressed through @rpath:
    # replace CMake's absolute install names with @rpath and let the loader search the bundle layout.
    set(CMAKE_MACOSX_RPATH ON)
    set(CMAKE_BUILD_WITH_INSTALL_RPATH OFF)
    set(CMAKE_INSTALL_RPATH_USE_LINK_PATH ON)
    # The install tree keeps its USD plugins, including the fallback-proxy libraries, under plugin/usd.
    set(CMAKE_INSTALL_RPATH "@loader_path/../lib" "@loader_path" "@loader_path/../plugin/opendcc"
                            "@loader_path/../plugin/usd")
    set(CMAKE_INSTALL_NAME_DIR "@rpath")

    # An external USD must win over a copy left in the dependency prefix: @rpath/libusd_* resolves in rpath order.
    if(DCC_DEPS_USD_EXTERNAL_LIB_DIR)
        list(APPEND CMAKE_INSTALL_RPATH "${DCC_DEPS_USD_EXTERNAL_LIB_DIR}")
    endif()

    # Dependencies built into the private prefix (qtadvanceddocking, Embree, Bullet) are not copied into the install
    # tree on macOS, so the installed binaries have to find them through the prefix itself.
    if(DCC_DEPS_PREFIX)
        list(APPEND CMAKE_INSTALL_RPATH "${DCC_DEPS_PREFIX}/lib")
    endif()

    # Each package installs its libraries into packages/<name>/lib and links libraries of other packages (the usd
    # editor tools all use common_tools). A dylib loaded from packages/A/lib therefore needs a search path to every
    # sibling package: dyld has no glob in rpaths, so the list is materialised here.
    file(GLOB _dcc_package_dirs LIST_DIRECTORIES true "${CMAKE_SOURCE_DIR}/src/packages/*")
    foreach(_dcc_package_dir IN LISTS _dcc_package_dirs)
        if(IS_DIRECTORY "${_dcc_package_dir}")
            get_filename_component(_dcc_package_name "${_dcc_package_dir}" NAME)
            list(APPEND CMAKE_INSTALL_RPATH "@loader_path/../../${_dcc_package_name}/lib")
        endif()
    endforeach()

    # GLEW pulls in the system <OpenGL/gl.h>, which Apple marks deprecated; the viewport uses those entry points
    # directly and there is no replacement for the fixed pipeline the renderer still relies on.
    add_compile_definitions(GL_SILENCE_DEPRECATION)
endif()
