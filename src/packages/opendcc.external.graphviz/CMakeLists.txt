set(PLUGIN_DIR ${CMAKE_INSTALL_PREFIX}/packages/opendcc.external.graphviz/)

install(
    DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/"
    DESTINATION "${PLUGIN_DIR}"
    FILES_MATCHING
    PATTERN "*.py")

install(DIRECTORY "${GRAPHVIZ_INCLUDE_DIR}" DESTINATION "${PLUGIN_DIR}")
install(
    DIRECTORY "${GRAPHVIZ_BINARY_DIR}"
    DESTINATION "${PLUGIN_DIR}"
    USE_SOURCE_PERMISSIONS)
if(NOT WIN32)
    install(
        DIRECTORY "${GRAPHVIZ_LIBRARY_DIR}"
        DESTINATION "${PLUGIN_DIR}"
        USE_SOURCE_PERMISSIONS)
endif()

file(READ package.toml CONTENTS)
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/package.toml "${CONTENTS}")
if(WIN32)
    file(READ package.win.toml CONTENTS)
    file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/package.toml "\n${CONTENTS}")
elseif(APPLE)
    # The unix manifest names the libraries a bundled graphviz ships on Linux (cairo, pango, the gvplugins). Homebrew
    # splits those into their own kegs, so only the graphviz libraries themselves are copied here; list what is actually
    # present, otherwise the loader reports every absent entry at startup. The unversioned names are the symlinks
    # Homebrew maintains, so only those are listed; the versioned files are copied alongside them for the loader to
    # resolve.
    file(
        GLOB _graphviz_libs
        RELATIVE "${GRAPHVIZ_LIBRARY_DIR}"
        "${GRAPHVIZ_LIBRARY_DIR}/lib*.dylib")
    foreach(_graphviz_lib IN LISTS _graphviz_libs)
        if(_graphviz_lib MATCHES "^lib[^.]*\\.dylib$")
            file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/package.toml "\n[[native.load]]\npath='lib/${_graphviz_lib}'\n")
        endif()
    endforeach()
elseif(UNIX)
    file(READ package.unix.toml CONTENTS)
    file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/package.toml "\n${CONTENTS}")
endif()
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/package.toml DESTINATION ${PLUGIN_DIR})
