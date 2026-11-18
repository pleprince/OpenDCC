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
    # The package loads its libraries by the paths package.toml names, so the library directory
    # is copied as-is, keeping whatever layout the distribution uses for the plugin libraries.
    # conda-forge keeps graphviz's plugin libraries in lib/graphviz, one level below the rest,
    # and their LC_RPATH is @loader_path/.. — correct there, wrong anywhere else, so package.toml
    # names them in that directory instead of them being copied out.
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
elseif(UNIX)
    file(READ package.unix.toml CONTENTS)
    file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/package.toml "\n${CONTENTS}")
endif()
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/package.toml DESTINATION ${PLUGIN_DIR})
