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
    # The package loads its libraries from <package>/lib by bare name, so the whole library
    # directory is copied. conda-forge's graphviz keeps the plugin libraries in lib/graphviz,
    # which package.toml also names as lib/<name>: flatten that directory into lib too.
    install(
        DIRECTORY "${GRAPHVIZ_LIBRARY_DIR}"
        DESTINATION "${PLUGIN_DIR}"
        USE_SOURCE_PERMISSIONS)
    if(IS_DIRECTORY "${GRAPHVIZ_LIBRARY_DIR}/graphviz")
        install(
            DIRECTORY "${GRAPHVIZ_LIBRARY_DIR}/graphviz/"
            DESTINATION "${PLUGIN_DIR}/lib"
            USE_SOURCE_PERMISSIONS)
    endif()
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
