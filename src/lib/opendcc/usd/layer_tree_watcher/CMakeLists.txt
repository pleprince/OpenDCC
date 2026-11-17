set(TARGET_NAME layer_tree_watcher)

add_library(
    ${TARGET_NAME} SHARED
    api.h
    layer_tree_watcher.h
    layer_tree_watcher.cpp
    layer_state_delegates_registry.h
    layer_state_delegates_registry.cpp
    layer_state_delegates_holder.h
    layer_state_delegates_holder.cpp)

target_compile_definitions(${TARGET_NAME} PRIVATE -DUSD_LAYER_TREE_WATCHER_EXPORT)

target_link_libraries(${TARGET_NAME} ${PYTHON_LIBRARY} ${Boost_PYTHON_LIBRARY} usd test_runner logging)
# The boost/python headers are a build requirement only: this target is installed with
# install(EXPORT), and an install interface may not name paths of the build environment.
target_include_directories(
    ${TARGET_NAME}
    PUBLIC "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/src/lib/>" "$<INSTALL_INTERFACE:include>"
           "$<BUILD_INTERFACE:${Boost_INCLUDE_DIRS}>" "$<BUILD_INTERFACE:${PYTHON_INCLUDE_DIRS}>")

install(
    TARGETS ${TARGET_NAME}
    EXPORT layer_tree_watcher-targets
    ARCHIVE DESTINATION "lib"
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION "lib")
if(MSVC)
    install(
        FILES $<TARGET_PDB_FILE:${TARGET_NAME}>
        DESTINATION bin
        OPTIONAL)
endif()
install(
    EXPORT layer_tree_watcher-targets
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/cmake/${TARGET_NAME}
    NAMESPACE opendcc::)
install(
    DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/include/opendcc/usd"
    FILES_MATCHING
    PATTERN "*.h")
