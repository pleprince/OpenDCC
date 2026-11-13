if(WIN32)
    set(OS_ENV_SEPARATOR ";")
    set(OS_LIBRARY_ENV_NAME "PATH")
elseif(APPLE)
    set(OS_ENV_SEPARATOR ":")
    # Mach-O uses DYLD_LIBRARY_PATH; LD_LIBRARY_PATH is ignored by dyld.
    set(OS_LIBRARY_ENV_NAME "DYLD_LIBRARY_PATH")
else()
    set(OS_ENV_SEPARATOR ":")
    set(OS_LIBRARY_ENV_NAME "LD_LIBRARY_PATH")
endif()

function(opendcc_add_package PACKAGE_NAME)
    set(OPENDCC_CURRENT_PACKAGE_NAME "${PACKAGE_NAME}")
    if(WIN32)
        # Keep Windows build paths short without changing source include roots or install destinations.
        add_subdirectory("${PACKAGE_NAME}" "${CMAKE_BINARY_DIR}/p/${PACKAGE_NAME}")
    else()
        add_subdirectory("${PACKAGE_NAME}")
    endif()
endfunction()

function(get_usd_env EXTRA_ENVIRONMENT USD_ENVIRONMENT_VAR)
    set(_result "")
    list(APPEND _result "${USD_LIBRARY_DIR}")
    list(APPEND _result "${Boost_LIBRARY_DIR_RELEASE}")
    # oneTBB installs runtime DLLs in bin; older TBB installs them in lib.
    list(APPEND _result "${TBB_INCLUDE_DIRS}/../lib")
    list(APPEND _result "${TBB_INCLUDE_DIRS}/../bin")
    list(APPEND _result "${USD_GENSCHEMA_DIR}")
    list(APPEND _result "${EXTRA_ENVIRONMENT}") # ????
    if(WIN32)
        list(APPEND _result "$ENV{PATH}")
    else()
        list(APPEND _result "$ENV{${OS_LIBRARY_ENV_NAME}}")
        list(APPEND _result "$ENV{PATH}")
    endif()
    string(JOIN "${OS_ENV_SEPARATOR}" _fixed_paths ${_result})

    set(${USD_ENVIRONMENT_VAR}
        "${_fixed_paths}"
        PARENT_SCOPE)
endfunction()

function(
    parse_schema_file
    SCHEMA_FILE
    USD_ENV
    OUTPUT_DIR
    GEN_HEADERS
    GEN_SRC
    GEN_SRC_PY
    SCHEMA_NAME
    SCHEMA_PREFIX
    HAVE_CLASSES)
    execute_process(
        COMMAND
            ${CMAKE_COMMAND} -E env "PYTHONPATH=${USD_LIBRARY_DIR}/python${OS_ENV_SEPARATOR}$ENV{PYTHONPATH}"
            "${OS_LIBRARY_ENV_NAME}=${USD_ENV}${OS_ENV_SEPARATOR}" "PATH=${USD_ENV}${OS_ENV_SEPARATOR}"
            "${PYTHON_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/cmake/macros/parse_usd_schema.py" "${USD_GENSCHEMA_SCRIPT}"
            "${SCHEMA_FILE}" "${OUTPUT_DIR}"
        RESULT_VARIABLE _exit_code
        OUTPUT_VARIABLE result
        ERROR_VARIABLE err_result ECHO_ERROR_VARIABLE)

    if(NOT _exit_code EQUAL "0")
        message(FATAL_ERROR "Failed to parse USD schema. ${_exit_code} returned.\n" "${result}")
    endif()
    string(REPLACE "\n" ";" result ${result})

    list(GET result 0 _schema_name)
    list(GET result 1 _schema_prefix)

    list(GET result 2 _gen_headers)
    string(REPLACE "," ";" _gen_headers ${_gen_headers})
    list(GET result 3 _gen_src)
    string(REPLACE "," ";" _gen_src ${_gen_src})
    list(GET result 4 _gen_src_py)
    string(REPLACE "," ";" _gen_src_py ${_gen_src_py})
    list(GET result 5 _have_classes)

    set(${SCHEMA_NAME}
        ${_schema_name}
        PARENT_SCOPE)
    set(${SCHEMA_PREFIX}
        ${_schema_prefix}
        PARENT_SCOPE)
    set(${GEN_HEADERS}
        ${_gen_headers}
        PARENT_SCOPE)
    set(${GEN_SRC}
        ${_gen_src}
        PARENT_SCOPE)
    set(${GEN_SRC_PY}
        ${_gen_src_py}
        PARENT_SCOPE)
    set(${HAVE_CLASSES}
        ${_have_classes}
        PARENT_SCOPE)
endfunction()

function(opendcc_make_python_module TARGET_NAME)
    set(options NO_BOOST_PYTHON)
    set(one_value_args PYMODULE_NAME VS_FOLDER PYMODULE_INSTALL_DIR PYMODULE_INSTALL_PATH)
    set(multi_value_args PYMODULE_SOURCES LIBRARY_DEPENDENCIES PUBLIC_DEFINITIONS PRIVATE_DEFINITIONS)

    cmake_parse_arguments(args "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})
    if(NOT args_PYMODULE_SOURCES OR NOT args_PYMODULE_NAME)
        return()
    endif()

    set(_pymodule_target ${TARGET_NAME})
    add_library(${_pymodule_target} SHARED ${args_PYMODULE_SOURCES})

    if(args_VS_FOLDER)
        make_folder(${args_VS_FOLDER} ${_pymodule_target})
    endif()
    if(MSVC)
        set(_pymodule_suffix ".pyd")
    else()
        set(_pymodule_suffix ".so")
    endif()

    target_compile_definitions(${_pymodule_target} PRIVATE PYMODULE_NAME=${args_PYMODULE_NAME})
    if(OPENDCC_CURRENT_PACKAGE_NAME)
        target_compile_definitions(${_pymodule_target} PRIVATE OPENDCC_PACKAGE_NAME="${OPENDCC_CURRENT_PACKAGE_NAME}")
    endif()
    if(args_NO_BOOST_PYTHON)
        target_link_libraries(${_pymodule_target} PUBLIC pybind11::pybind11 Python3::Python)
    else()
        target_link_libraries(${_pymodule_target} PUBLIC pybind11::pybind11 ${Boost_PYTHON_LIBRARY} ${PYTHON_LIBRARY})
    endif()
    target_link_libraries(${TARGET_NAME} PUBLIC ${args_LIBRARY_DEPENDENCIES})

    if(args_PUBLIC_DEFINITIONS)
        target_compile_definitions(${TARGET_NAME} PUBLIC ${args_PUBLIC_DEFINITIONS})
    endif()
    if(args_PRIVATE_DEFINITIONS)
        target_compile_definitions(${TARGET_NAME} PRIVATE ${args_PRIVATE_DEFINITIONS})
    endif()
    set_target_properties(
        ${_pymodule_target}
        PROPERTIES PREFIX ""
                   SUFFIX ${_pymodule_suffix}
                   OUTPUT_NAME ${args_PYMODULE_NAME}
                   ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${_pymodule_target}"
                   RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${_pymodule_target}"
                   LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${_pymodule_target}"
                   PDB_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${_pymodule_target}"
                   CLEAN_DIRECT_OUTPUT 1)

    if(args_PYMODULE_INSTALL_PATH)
        install(FILES "$<TARGET_FILE:${_pymodule_target}>"
                DESTINATION "${CMAKE_INSTALL_PREFIX}/${args_PYMODULE_INSTALL_PATH}")

        if(MSVC)
            install(
                FILES "$<TARGET_PDB_FILE:${_pymodule_target}>"
                DESTINATION "${CMAKE_INSTALL_PREFIX}/${args_PYMODULE_INSTALL_PATH}"
                OPTIONAL)
        endif()

    else()
        if(NOT args_PYMODULE_INSTALL_DIR)
            message(
                WARNING
                    "PYMODULE_INSTALL_DIR for target ${TARGET_NAME} is not set. Default directory 'opendcc' will be used."
            )
            set(args_PYMODULE_INSTALL_DIR opendcc)
        endif()

        install(FILES "$<TARGET_FILE:${_pymodule_target}>"
                DESTINATION "${DCC_PYTHON_INSTALL_SITE_PACKAGES_ROOT}/${args_PYMODULE_INSTALL_DIR}")

        if(MSVC)
            install(
                FILES "$<TARGET_PDB_FILE:${_pymodule_target}>"
                DESTINATION "${DCC_PYTHON_INSTALL_SITE_PACKAGES_ROOT}/${args_PYMODULE_INSTALL_DIR}"
                OPTIONAL)
        endif()
    endif()
endfunction()

function(opendcc_make_library TARGET_NAME)
    set(options QT_AUTOMOC PYMODULE_NO_BOOST_PYTHON)
    set(one_value_args
        TYPE # static shared plugin
        VS_FOLDER
        PLUGIN_DIR # deprecated: use PACKAGE_DIR instead
        PACKAGE_DIR
        PYMODULE_NAME
        PYMODULE_INSTALL_DIR
        PYMODULE_INSTALL_PATH
        RESOURCES_DIR)

    set(multi_value_args
        PUBLIC_HEADERS
        PRIVATE_HEADERS
        CPPFILES
        LIBRARY_DEPENDENCIES
        INCLUDE_DIRS
        PUBLIC_DEFINITIONS
        PRIVATE_DEFINITIONS
        RESOURCES
        PYMODULE_SOURCES)

    cmake_parse_arguments(args "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})

    if(NOT args_TYPE)
        set(args_TYPE "SHARED")
    endif()

    string(TOLOWER ${args_TYPE} args_TYPE)

    if(${args_TYPE} STREQUAL "plugin")
        set(_library_type "SHARED")
    else()
        string(TOUPPER ${args_TYPE} _library_type)
    endif()

    add_library(${TARGET_NAME} ${_library_type} ${args_PUBLIC_HEADERS} ${args_PRIVATE_HEADERS} ${args_CPPFILES})

    if(OPENDCC_CURRENT_PACKAGE_NAME)
        target_compile_definitions(${TARGET_NAME} PRIVATE OPENDCC_PACKAGE_NAME="${OPENDCC_CURRENT_PACKAGE_NAME}")
    endif()

    if(args_PUBLIC_DEFINITIONS)
        target_compile_definitions(${TARGET_NAME} PUBLIC ${args_PUBLIC_DEFINITIONS})
    endif()
    if(args_PRIVATE_DEFINITIONS)
        target_compile_definitions(${TARGET_NAME} PRIVATE ${args_PRIVATE_DEFINITIONS})
    endif()

    if(args_QT_AUTOMOC)
        set_property(TARGET ${TARGET_NAME} PROPERTY AUTOMOC ON)
        # Windows MAX_PATH: the default autogen path runs past 260 chars in a deep tree and cl.exe then cannot open
        # moc_<header>.cpp. Keep it short rather than depend on the checkout depth.
        set_property(TARGET ${TARGET_NAME} PROPERTY AUTOGEN_BUILD_DIR "${CMAKE_BINARY_DIR}/ag/${TARGET_NAME}")
    endif()

    target_include_directories(${TARGET_NAME} PUBLIC ${args_INCLUDE_DIRS})

    target_link_libraries(${TARGET_NAME} PUBLIC ${args_LIBRARY_DEPENDENCIES})

    if(args_VS_FOLDER)
        make_folder(${args_VS_FOLDER} ${TARGET_NAME})
    endif()

    # install configuration
    if(((${args_TYPE} STREQUAL "static") OR (${args_TYPE} STREQUAL "shared")) AND NOT DEFINED args_PACKAGE_DIR)
        set(_runtime_destination bin)
        set(_library_destination lib)
        set(_archive_destination lib)
        set(_plugin_dir plugin/opendcc)
    else()
        if(DEFINED args_PLUGIN_DIR)
            set(_runtime_destination plugin/${args_PLUGIN_DIR})
            set(_library_destination plugin/${args_PLUGIN_DIR})
            set(_archive_destination plugin/${args_PLUGIN_DIR})
            set(_plugin_dir plugin/${args_PLUGIN_DIR})
        elseif(DEFINED args_PACKAGE_DIR)
            set(_runtime_destination packages/${args_PACKAGE_DIR})
            set(_library_destination packages/${args_PACKAGE_DIR})
            set(_archive_destination packages/${args_PACKAGE_DIR})
            set(_plugin_dir packages/${args_PACKAGE_DIR})
        else()
            message(FATAL_ERROR "args_PLUGIN_DIR nor args_PACKAGE_DIR is not set.")
        endif()
    endif()

    install(
        TARGETS ${TARGET_NAME}
        EXPORT ${TARGET_NAME}-targets
        RUNTIME DESTINATION ${_runtime_destination}
        LIBRARY DESTINATION ${_library_destination}
        ARCHIVE DESTINATION ${_archive_destination})
    if(MSVC)
        if(${_library_type} STREQUAL "SHARED")
            install(
                FILES "$<TARGET_PDB_FILE:${TARGET_NAME}>"
                DESTINATION ${_runtime_destination}
                OPTIONAL)
        else()
            install(
                FILES "$<TARGET_FILE_DIR:${TARGET_NAME}>/$<TARGET_FILE_NAME:${TARGET_NAME}>.pdb"
                DESTINATION ${_library_destination}
                OPTIONAL)
        endif()
    endif()

    # resource install
    set(_target_install_plugin_dir "${CMAKE_INSTALL_PREFIX}/${_plugin_dir}/${TARGET_NAME}")

    if(WIN32)
        set(_binary_install_dir "${CMAKE_INSTALL_PREFIX}/${_runtime_destination}")
    else()
        set(_binary_install_dir "${CMAKE_INSTALL_PREFIX}/${_library_destination}")
    endif()
    set(_resources_install_path "${_target_install_plugin_dir}")
    if(DEFINED args_RESOURCES_DIR)
        set(_resources_install_path "${CMAKE_INSTALL_PREFIX}/${args_RESOURCES_DIR}")
    endif()
    foreach(_resource_file ${args_RESOURCES})
        get_filename_component(_resource_dir ${_resource_file} PATH)
        get_filename_component(_resource_name ${_resource_file} NAME)

        if(${_resource_name} STREQUAL "plugInfo.json")
            file(RELATIVE_PATH LIBRARY_LOCATION "${_resources_install_path}/.." "${_binary_install_dir}")
            configure_file(${_resource_file} "${CMAKE_CURRENT_BINARY_DIR}/${_resource_file}" @ONLY)
            set(_resource_file "${CMAKE_CURRENT_BINARY_DIR}/${_resource_file}")
        endif()
        install(FILES ${_resource_file} DESTINATION "${_resources_install_path}")
    endforeach()
    if(${_library_type} STREQUAL "SHARED")
        set(_pymodule_options)
        if(args_PYMODULE_NO_BOOST_PYTHON)
            list(APPEND _pymodule_options NO_BOOST_PYTHON)
        endif()
        opendcc_make_python_module(
            ${TARGET_NAME}_py
            ${_pymodule_options}
            PYMODULE_NAME
            ${args_PYMODULE_NAME}
            PYMODULE_SOURCES
            ${args_PYMODULE_SOURCES}
            PYMODULE_INSTALL_DIR
            "${args_PYMODULE_INSTALL_DIR}"
            PYMODULE_INSTALL_PATH
            "${args_PYMODULE_INSTALL_PATH}"
            VS_FOLDER
            ${args_VS_FOLDER}
            LIBRARY_DEPENDENCIES
            ${TARGET_NAME})
    endif()
endfunction()

function(opendcc_make_usd_schema TARGET_NAME)
    set(options "")
    set(one_value_args
        VS_FOLDER
        PLUGIN_DIR # deprecated: use PACKAGE_DIR instead
        PACKAGE_DIR
        CUSTOM_RUNTIME_DIR
        SCHEMA_FILE # default schema.usda
        HEADER_INSTALL_DIR # TODO: Reconsider this mechanism. Evaluate this variable based on source directory.
        SRC_GENERATION_DIR # TODO: Reconsider this mechanism. Evaluate this variable based on source directory.
        PYTHON_INSTALL_DIR)
    set(multi_value_args
        PYMODULE_CPPFILES
        EXTRA_USD_ENVIRONMENT
        PUBLIC_HEADERS
        PRIVATE_HEADERS
        CPPFILES
        AFTER_GEN_SCRIPT
        INCLUDE_DIRS
        SCHEMA_DEPENDENCIES
        LIBRARY_DEPENDENCIES
        PUBLIC_DEFINITIONS
        PRIVATE_DEFINITIONS
        PYTHON_FILES)

    cmake_parse_arguments(args "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})

    if(NOT args_SCHEMA_FILE)
        set(args_SCHEMA_FILE "schema.usda")
    endif()

    if(args_SRC_GENERATION_DIR)
        set(_output_dir_name "${args_SRC_GENERATION_DIR}")
    else()
        get_filename_component(_output_dir_name "${CMAKE_CURRENT_BINARY_DIR}" NAME)
    endif()
    set(_output_dir "${CMAKE_CURRENT_BINARY_DIR}/generated_src/${_output_dir_name}")
    set(_schema_sources_include_dir "${CMAKE_CURRENT_BINARY_DIR}/generated_src")
    set(_schema_file "${CMAKE_CURRENT_SOURCE_DIR}/${args_SCHEMA_FILE}")

    if(DEFINED args_PLUGIN_DIR)
        set(_schema_install_dir "plugin/${args_PLUGIN_DIR}")
    elseif(DEFINED args_PACKAGE_DIR)
        set(_schema_install_dir "packages/${args_PACKAGE_DIR}")
    else()
        message(FATAL_ERROR "args_PLUGIN_DIR nor args_PACKAGE_DIR is not set.")
    endif()
    get_usd_env(${args_EXTRA_USD_ENVIRONMENT} "" _usd_env)

    parse_schema_file(
        ${_schema_file}
        "${_usd_env}"
        ${_output_dir}
        _gen_headers
        _gen_src
        _gen_src_py
        _schema_name
        _schema_prefix
        _have_classes)

    file(
        GENERATE
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/configure_plugInfo.cmake"
        CONTENT
            "configure_file(\"${_output_dir}/plugInfo.json.in\" \"${CMAKE_CURRENT_BINARY_DIR}/${_schema_install_dir}/${_schema_name}/resources/plugInfo.json\" @ONLY)"
    )

    # usdGenSchema does not write a plugInfo.json when schema.usda declares no classes, so expand USD's own codegen
    # template for that case.
    if(NOT _have_classes)
        find_file(
            USD_PLUG_INFO_TEMPLATE
            NAMES plugInfo.json
            PATHS "${USD_LIBRARY_DIR}/usd/usd/resources/codegenTemplates" "${USD_ROOT}/share/usd/codegenTemplates"
            NO_DEFAULT_PATH)
        if(NOT USD_PLUG_INFO_TEMPLATE)
            message(
                FATAL_ERROR "USD's plugInfo.json codegen template was not found; looked in "
                            "${USD_LIBRARY_DIR}/usd/usd/resources/codegenTemplates and "
                            "${USD_ROOT}/share/usd/codegenTemplates")
        endif()
        set(_run_pre_gen_script
            "${CMAKE_COMMAND}" "-DPLUG_INFO_TEMPLATE=${USD_PLUG_INFO_TEMPLATE}"
            "-DLIBRARY_NAME=${_schema_name}" "-DOUTPUT=${_output_dir}/plugInfo.json" -P
            "${CMAKE_SOURCE_DIR}/cmake/macros/generate_empty_plug_info.cmake")
    else()
        set(_run_pre_gen_script "${CMAKE_COMMAND}" -E true)
    endif()

    if(args_AFTER_GEN_SCRIPT)
        list(GET args_AFTER_GEN_SCRIPT 0 _after_gen_script_path)
        list(SUBLIST args_AFTER_GEN_SCRIPT 1 -1 _after_gen_script_args)
        set(_run_after_gen_script "${PYTHON_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/${_after_gen_script_path}"
                                  ${_after_gen_script_args})
    else()
        set(_run_after_gen_script "${CMAKE_COMMAND}" -E true)
    endif()

    if(DCC_KATANA_SUPPORT)
        set(_pxr_path_name FNPXR_PLUGINPATH)
    else()
        set(_pxr_path_name PXR_PLUGINPATH_NAME)
    endif()

    if(args_SCHEMA_DEPENDENCIES)
        set(_pxr_deps "")
        foreach(_target ${args_SCHEMA_DEPENDENCIES})
            list(APPEND _pxr_deps "$<TARGET_FILE_DIR:${_target}>")
        endforeach()
    endif()

    set(_target_install_plugin_dir "${CMAKE_INSTALL_PREFIX}/${_schema_install_dir}/${_schema_name}")

    if(args_CUSTOM_RUNTIME_DIR)
        set(_runtime_dir ${args_CUSTOM_RUNTIME_DIR})
    else()
        set(_runtime_dir ${_schema_install_dir})
    endif()

    file(RELATIVE_PATH LIBRARY_LOCATION "${_target_install_plugin_dir}" "${CMAKE_INSTALL_PREFIX}/${_runtime_dir}")
    set(PLUG_INFO_ROOT ..)
    set(PLUG_INFO_RESOURCE_PATH resources)
    set(PLUG_INFO_LIBRARY_PATH
        "${LIBRARY_LOCATION}/${CMAKE_SHARED_LIBRARY_PREFIX}${TARGET_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX}")

    add_custom_command(
        OUTPUT "${_output_dir}/plugInfo.json" "${_output_dir}/generatedSchema.usda"
               "${CMAKE_CURRENT_BINARY_DIR}/${_schema_install_dir}/${_schema_name}/resources/plugInfo.json"
               ${_gen_headers} ${_gen_src} ${_gen_src_py}
        DEPENDS ${_schema_file} "${_after_gen_script_path}" ${args_SCHEMA_DEPENDENCIES}
        COMMAND ${CMAKE_COMMAND} -E make_directory "${_output_dir}"
        COMMAND
            ${CMAKE_COMMAND} -E env "PYTHONPATH=${USD_LIBRARY_DIR}/python${OS_ENV_SEPARATOR}$ENV{PYTHONPATH}"
            "${OS_LIBRARY_ENV_NAME}=${_usd_env}${OS_ENV_SEPARATOR}" "PATH=${_usd_env}${OS_ENV_SEPARATOR}"
            "${_pxr_path_name}=${_pxr_deps}" ${_run_pre_gen_script}
        COMMAND
            ${CMAKE_COMMAND} -E env "PYTHONPATH=${USD_LIBRARY_DIR}/python${OS_ENV_SEPARATOR}$ENV{PYTHONPATH}"
            "${OS_LIBRARY_ENV_NAME}=${_usd_env}${OS_ENV_SEPARATOR}" "PATH=${_usd_env}${OS_ENV_SEPARATOR}"
            "${_pxr_path_name}=${_pxr_deps}" ${USD_GENSCHEMA} "${_schema_file}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${_output_dir}/plugInfo.json ${_output_dir}/plugInfo.json.in
        COMMAND
            ${CMAKE_COMMAND} -E env "PYTHONPATH=${USD_LIBRARY_DIR}/python${OS_ENV_SEPARATOR}$ENV{PYTHONPATH}"
            "${OS_LIBRARY_ENV_NAME}=${_usd_env}${OS_ENV_SEPARATOR}" "PATH=${_usd_env}${OS_ENV_SEPARATOR}"
            "${_pxr_path_name}=${_pxr_deps}" ${_run_after_gen_script}
        COMMAND
            ${CMAKE_COMMAND} -DPLUG_INFO_ROOT=${PLUG_INFO_ROOT} -DPLUG_INFO_RESOURCE_PATH=${PLUG_INFO_RESOURCE_PATH}
            -DPLUG_INFO_LIBRARY_PATH=${PLUG_INFO_LIBRARY_PATH} -P "${CMAKE_CURRENT_BINARY_DIR}/configure_plugInfo.cmake"
        WORKING_DIRECTORY "${_output_dir}")

    set(TARGET_NAME_PY ${TARGET_NAME}_py)

    set(_public_headers ${_gen_headers} ${args_PUBLIC_HEADERS})
    set(_src ${_gen_src} ${args_CPPFILES})
    set(_src_py ${_gen_src_py} ${args_PYMODULE_CPPFILES})
    add_library(${TARGET_NAME} SHARED ${_public_headers} ${args_PRIVATE_HEADERS} ${_src})

    add_library(${TARGET_NAME_PY} SHARED ${_public_headers} ${args_PRIVATE_HEADERS} ${_src_py})

    set_target_properties(${TARGET_NAME} PROPERTIES PUBLIC_HEADER "${_public_headers}")

    # Third-party include directories are build-only: they are absolute paths into whatever prefix the dependencies live
    # in, so exporting them would make the installed target point at a machine-local tree (and CMake rejects a prefix
    # that sits inside the source tree).
    target_include_directories(
        ${TARGET_NAME}
        PUBLIC $<BUILD_INTERFACE:${Boost_INCLUDE_DIRS}>
               $<BUILD_INTERFACE:${PYTHON_INCLUDE_DIRS}>
               $<BUILD_INTERFACE:${USD_INCLUDE_DIR}>
               $<BUILD_INTERFACE:${TBB_INCLUDE_DIR}>
               ${args_INCLUDE_DIRS}
               $<BUILD_INTERFACE:${_schema_sources_include_dir}>
               $<BUILD_INTERFACE:${_output_dir}>)

    target_link_libraries(
        ${TARGET_NAME}
        ${TBB_LIBRARIES}
        ${Boost_PYTHON_LIBRARY}
        ${PYTHON_LIBRARY}
        ${args_LIBRARY_DEPENDENCIES}
        usd
        usdGeom)

    if(args_VS_FOLDER)
        make_folder(${args_VS_FOLDER} ${TARGET_NAME} ${TARGET_NAME_PY})
    endif()

    string(TOUPPER ${_schema_name} _export_define)
    target_compile_definitions(${TARGET_NAME} PRIVATE ${args_PRIVATE_DEFINITIONS} ${_export_define}_EXPORTS)
    if(args_PUBLIC_DEFINITIONS)
        target_compile_definitions(${TARGET_NAME} PUBLIC ${args_PUBLIC_DEFINITIONS})
    endif()

    target_link_libraries(${TARGET_NAME_PY} ${TARGET_NAME})

    # configure another plugInfo for other targets that might use this plugin during their config
    set(PLUG_INFO_ROOT .)
    set(PLUG_INFO_RESOURCE_PATH resources)
    set(PLUG_INFO_LIBRARY_PATH "./${CMAKE_SHARED_LIBRARY_PREFIX}${TARGET_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX}")
    file(
        GENERATE
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/configure_internal_plugInfo.cmake"
        CONTENT
            "configure_file(\"${_output_dir}/plugInfo.json.in\" \"${CMAKE_CURRENT_BINARY_DIR}/plugInfo_internal.json\" @ONLY)"
    )

    add_custom_command(
        TARGET ${TARGET_NAME}
        POST_BUILD
        COMMAND
            ${CMAKE_COMMAND} -DPLUG_INFO_ROOT=${PLUG_INFO_ROOT} -DPLUG_INFO_RESOURCE_PATH=${PLUG_INFO_RESOURCE_PATH}
            -DPLUG_INFO_LIBRARY_PATH=${PLUG_INFO_LIBRARY_PATH} -P
            "${CMAKE_CURRENT_BINARY_DIR}/configure_internal_plugInfo.cmake"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_BINARY_DIR}/plugInfo_internal.json"
                "$<TARGET_FILE_DIR:${TARGET_NAME}>/plugInfo.json"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_schema_file}"
                "$<TARGET_FILE_DIR:${TARGET_NAME}>/resources/${_schema_name}/schema.usda")

    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${_schema_install_dir}/${_schema_name}/resources/plugInfo.json"
            DESTINATION "${CMAKE_INSTALL_PREFIX}/${_schema_install_dir}/${_schema_name}/resources/")
    install(FILES "${_output_dir}/generatedSchema.usda" DESTINATION "${_schema_install_dir}/${_schema_name}/resources/")
    export(TARGETS ${TARGET_NAME} FILE ${TARGET_NAME}.cmake)
    install(FILES ${_schema_file} DESTINATION ${_schema_install_dir}/${_schema_name}/resources/${_schema_name})
    install(
        TARGETS ${TARGET_NAME}
        EXPORT ${TARGET_NAME}-targets
        ARCHIVE DESTINATION ${_runtime_dir}
        LIBRARY DESTINATION ${_runtime_dir}
        RUNTIME DESTINATION ${_runtime_dir}
        PUBLIC_HEADER DESTINATION ${args_HEADER_INSTALL_DIR})

    if(args_PYTHON_INSTALL_DIR)
        set(_python_install_dir "${args_PYTHON_INSTALL_DIR}")
    else()
        set(_python_install_dir "${DCC_PYTHON_INSTALL_SITE_PACKAGES_ROOT}")
    endif()

    install(
        EXPORT ${TARGET_NAME}-targets
        DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/${TARGET_NAME}"
        NAMESPACE opendcc::)
    if(MSVC)
        install(
            FILES "$<TARGET_PDB_FILE:${TARGET_NAME}>"
            DESTINATION ${_runtime_dir}
            OPTIONAL)
        install(
            FILES "$<TARGET_PDB_FILE:${TARGET_NAME_PY}>"
            DESTINATION "${_python_install_dir}/${_schema_prefix}"
            OPTIONAL)
    endif()

    if(MSVC)
        set(_pymodule_suffix ".pyd")
    else()
        set(_pymodule_suffix ".so")
    endif()
    set_target_properties(
        ${TARGET_NAME_PY}
        PROPERTIES PREFIX ""
                   OUTPUT_NAME _${_schema_name}
                   SUFFIX ${_pymodule_suffix})
    target_compile_definitions(
        ${TARGET_NAME_PY} PRIVATE MFB_PACKAGE_NAME=${_schema_name} MFB_ALT_PACKAGE_NAME=${_schema_name}
                                  MFB_PACKAGE_MODULE=_${_schema_name})
    install(
        TARGETS ${TARGET_NAME_PY}
        LIBRARY DESTINATION "${_python_install_dir}/${_schema_prefix}"
        RUNTIME DESTINATION "${_python_install_dir}/${_schema_prefix}")
    if(args_PYTHON_FILES)
        # todo: check if __init__.py exists
        install(FILES ${args_PYTHON_FILES} DESTINATION "${_python_install_dir}/${_schema_prefix}")
    endif()

endfunction()

# Reads a shiboken typesystem and derives everything the generated bindings need. The package attribute names the
# python package ("opendcc.ui.node_editor._node_editor"); the namespace is always "opendcc", the trailing component
# is the module, and the rest is the directory the wrappers land in.
function(
    opendcc_parse_typesystem
    TYPESYSTEM_FILE
    OUTPUT_DIR
    MODULE_NAME
    SRC_PATH
    HEADERS
    SOURCES
    TYPESYSTEMS)
    file(READ "${TYPESYSTEM_FILE}" _xml)
    string(REGEX MATCH "<typesystem[^>]*package=\"[^\"]*\"" _package_element "${_xml}")
    if(NOT _package_element)
        message(FATAL_ERROR "${TYPESYSTEM_FILE} has no <typesystem package=\"...\"> element")
    endif()
    string(REGEX REPLACE ".*package=\"([^\"]*)\".*" "\\1" _package "${_package_element}")

    string(REPLACE "." ";" _parts "${_package}")
    list(LENGTH _parts _part_count)
    if(_part_count LESS 2)
        message(FATAL_ERROR "${TYPESYSTEM_FILE}: package \"${_package}\" is not <namespace>.<module>")
    endif()
    list(GET _parts -1 _module_name)
    # Everything after the leading namespace is the subdirectory of the python package, module included: shiboken
    # writes the wrappers next to the module it generates.
    set(_package_path "")
    math(EXPR _last_part "${_part_count}-1")
    foreach(_index RANGE 1 ${_last_part})
        list(GET _parts ${_index} _part)
        list(APPEND _package_path "${_part}")
    endforeach()

    set(_directory "${OUTPUT_DIR}/opendcc")
    set(_source_directory "opendcc")
    foreach(_part IN LISTS _package_path)
        set(_directory "${_directory}/${_part}")
        set(_source_directory "${_source_directory}/${_part}")
    endforeach()
    string(REPLACE "\\" "/" _directory "${_directory}")
    string(REPLACE "\\" "/" _source_directory "${_source_directory}")

    # load-typesystem first, in document order, then every object-type followed by every value-type: that is the
    # order shiboken's project file and the generated file list have always used.
    set(_typesystems "")
    string(REGEX MATCHALL "<load-typesystem[^>]*name=\"[^\"]*\"" _load_typesystems "${_xml}")
    foreach(_element IN LISTS _load_typesystems)
        string(REGEX REPLACE ".*name=\"([^\"]*)\".*" "\\1" _type_system "${_element}")
        list(APPEND _typesystems "${_type_system}")
    endforeach()
    set(_type_names "")
    foreach(_element_name object-type value-type)
        string(REGEX MATCHALL "<${_element_name}[^>]*name=\"[^\"]*\"" _elements "${_xml}")
        foreach(_element IN LISTS _elements)
            string(REGEX REPLACE ".*name=\"([^\"]*)\".*" "\\1" _type_name "${_element}")
            list(APPEND _type_names "${_type_name}")
        endforeach()
    endforeach()

    set(_headers "")
    set(_sources "")
    foreach(_type_name IN LISTS _type_names)
        string(TOLOWER "${_type_name}" _type_slug)
        list(APPEND _headers "${_directory}/opendcc_${_type_slug}_wrapper.h")
        list(APPEND _sources "${_directory}/opendcc_${_type_slug}_wrapper.cpp")
    endforeach()
    string(REPLACE ";" "_" _package_slug "${_package_path}")
    list(APPEND _headers "${_directory}/opendcc_${_package_slug}_python.h")
    list(APPEND _sources "${_directory}/${_module_name}_module_wrapper.cpp")

    set(${MODULE_NAME}
        ${_module_name}
        PARENT_SCOPE)
    set(${SRC_PATH}
        ${_source_directory}
        PARENT_SCOPE)
    set(${HEADERS}
        ${_headers}
        PARENT_SCOPE)
    set(${SOURCES}
        ${_sources}
        PARENT_SCOPE)
    set(${TYPESYSTEMS}
        ${_typesystems}
        PARENT_SCOPE)
endfunction()

# Writes the shiboken project template (side_config.txt.in) that configure_file then fills in for one target.
# EXTRA is the shiboken warning mode: "silent" or "no-suppress-warnings".
function(opendcc_write_side_config OUTPUT_DIR INCLUDE_PATHS TYPESYSTEM_PATHS EXTRA)
    set(_include_lines "")
    foreach(_include_path IN LISTS INCLUDE_PATHS)
        if(NOT _include_path STREQUAL "")
            list(APPEND _include_lines "include-path = ${_include_path}")
        endif()
    endforeach()
    set(_typesystem_lines "")
    foreach(_typesystem_path IN LISTS TYPESYSTEM_PATHS)
        if(NOT _typesystem_path STREQUAL "")
            list(APPEND _typesystem_lines "typesystem-path = ${_typesystem_path}")
        endif()
    endforeach()
    string(JOIN "\n" _include_text ${_include_lines})
    string(JOIN "\n" _typesystem_text ${_typesystem_lines})

    file(
        WRITE "${OUTPUT_DIR}/side_config.txt.in"
        "[generator-project]\n"
        "\n"
        "generator-set = shiboken\n"
        "enable-pyside-extensions\n"
        "enable-parent-ctor-heuristic\n"
        "enable-return-value-heuristic\n"
        "avoid-protected-hack\n"
        "use-isnull-as-nb_nonzero\n"
        "debug-level = full\n"
        "\n"
        "${EXTRA}\n"
        "\n"
        "header-file = @HEADER_FILE_PATH@\n"
        "typesystem-file = @TYPESYSTEM_FILE_PATH@\n"
        "language-level = c++@CMAKE_CXX_STANDARD@\n"
        "${_include_text}\n"
        "typesystem-path = @PYSIDE_TYPESYSTEMS@\n"
        "${_typesystem_text}\n"
        "framework-include-path = @DCC_QT_INSTALL_PREFIX@/lib\n")
endfunction()

function(opendcc_make_shiboken_bindings TARGET_NAME)
    set(options VERBOSE
                # QT_AUTOMOC
    )
    set(one_value_args TARGET SOURCE_DIR LEGACY_HEADER_FILEPATH CUSTOM_PROJECT_FILE VS_FOLDER PYTHON_INSTALL_DIR)
    set(multi_value_args GLUE_FILES LIBRARY_DEPENDENCIES INCLUDE_DIRS PUBLIC_DEFINITIONS PRIVATE_DEFINITIONS
                         GEN_CONFIG_INCLUDE_DIRS)

    cmake_parse_arguments(args "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})
    if(args_VERBOSE)
        message(STATUS "Generating sources for ${TARGET_NAME}:")
    endif()

    if(args_PYMODULE_INSTALL_DIR)
        set(_py_install_dir "${args_PYMODULE_INSTALL_DIR}")
    else()
        set(_py_install_dir opendcc)
    endif()

    # gather include paths for generation wrap files
    get_target_property(PYSIDE_INCLUDE_DIR ${DCC_PYSIDE_TARGET} INTERFACE_INCLUDE_DIRECTORIES)
    # Third-party headers are passed as system includes: shiboken refuses to extract anything it cannot model, and
    # oneTBB's enumerable_thread_specific (reached through USD) makes it fail with "Failed to determine template
    # parameter of ets_base<>", which aborts generation for every header that includes USD. Headers found through a
    # system include path are skipped instead of modelled.
    set(_shiboken_system_includes
        "${PYTHON_INCLUDE_DIR}"
        "${PXR_INCLUDE_DIRS}"
        "${Boost_INCLUDE_DIRS}"
        "${TBB_INCLUDE_DIRS}"
        "${OIIO_INCLUDE_DIR}"
        # OpenImageIO's headers include <fmt/format.h>; the vendored shim is the only copy that coexists with spdlog's
        # bundled fmt, and it has to be visible to the parser.
        "${PROJECT_SOURCE_DIR}/src/lib/opendcc/base/vendor/fmt-shim"
        "${pybind11_INCLUDE_DIRS}")
    set(_gen_side_config_includes "${PROJECT_BINARY_DIR}/include" "${PROJECT_SOURCE_DIR}/src/lib"
                                  "${PYSIDE_INCLUDE_DIR}" "${DCC_QT_INCLUDE_DIRS}")

    if(args_GEN_CONFIG_INCLUDE_DIRS)
        foreach(include_dir ${args_GEN_CONFIG_INCLUDE_DIRS})
            list(APPEND _gen_side_config_includes ${include_dir})
        endforeach()
    endif()

    # find all dependent typesystems and generate list of source files
    set(_typesystem_filepath "${args_SOURCE_DIR}/${args_TARGET}.xml")
    if(args_LEGACY_HEADER_FILEPATH)
        set(_shiboken_header_filepath "${args_SOURCE_DIR}/${args_LEGACY_HEADER_FILEPATH}")
    else()
        set(_shiboken_header_filepath "${args_SOURCE_DIR}/${args_TARGET}.h")
    endif()
    opendcc_parse_typesystem("${CMAKE_CURRENT_SOURCE_DIR}/${_typesystem_filepath}"
                             "${CMAKE_CURRENT_BINARY_DIR}/wrap" _module_name _src_path _headers _sources
                             _dependent_typesystems)
    if(args_VERBOSE)
        message(STATUS "    Parsed ${_typesystem_filepath}:")
        message(STATUS "        Module name: ${_module_name}")
        message(STATUS "        Generated sources path: ${CMAKE_CURRENT_BINARY_DIR}/wrap/${_src_path}")
        message(STATUS "        Expected headers: ${_headers}")
        message(STATUS "        Expected sources: ${_sources}")
        message(STATUS "        Dependent typesystems: ${_dependent_typesystems}")
    endif()

    # gather dependent typesystem paths
    foreach(_ts ${_dependent_typesystems})
        get_filename_component(_target_name ${_ts} NAME_WLE)
        set(_target_name ${_target_name}_py)
        if(TARGET ${_target_name})
            get_target_property(_ts_path ${_target_name} PYSIDE_TYPESYSTEM_PATH)
            if(NOT _ts_path)
                message(
                    WARNING
                        "Typesystem file for target ${_target_name} not found. Shiboken generation error might happen.")
            else()
                get_target_property(_ts_sources_dir ${_target_name} PYSIDE_SOURCES_DIR)
                get_filename_component(_ts_directory "${_ts_path}" DIRECTORY)
                list(APPEND _typesystem_paths "${_ts_directory}")
                list(APPEND _gen_side_config_includes "${_ts_sources_dir}")
                list(APPEND _typesystem_includes "${_ts_sources_dir}")
                list(APPEND _dependent_pyside_modules ${target_name})
            endif()
        endif()
    endforeach()

    set(_output_dir "${CMAKE_CURRENT_BINARY_DIR}")

    # The typesystem differs between Qt5 and Qt6 (DCC_QT_SEQ_CONTAINER), so configure it into the build tree and point
    # shiboken and PYSIDE_TYPESYSTEM_PATH at that copy.
    set(_typesystem_source "${CMAKE_CURRENT_SOURCE_DIR}/${_typesystem_filepath}")
    get_filename_component(_typesystem_name "${_typesystem_filepath}" NAME)
    set(_typesystem_generated "${_output_dir}/${_typesystem_name}")
    configure_file("${_typesystem_source}" "${_typesystem_generated}" @ONLY)
    # generate side_config.txt.in with all dependent typesystem and includes
    if(args_CUSTOM_PROJECT_FILE)
        message(STATUS "Using custom project file ${args_CUSTOM_PROJECT_FILE}...")
        set(_side_config_file "${args_CUSTOM_PROJECT_FILE}")
    else()
        if(args_VERBOSE)
            set(_verbose "no-suppress-warnings")
        else()
            set(_verbose "silent")
        endif()

        opendcc_write_side_config("${CMAKE_CURRENT_BINARY_DIR}" "${_gen_side_config_includes}" "${_typesystem_paths}"
                                  "${_verbose}")
        if(args_VERBOSE)
            message(STATUS "    Wrote ${CMAKE_CURRENT_BINARY_DIR}/side_config.txt.in")
        endif()

        set(TYPESYSTEM_FILE_PATH "${_typesystem_generated}")
        set(HEADER_FILE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/${_shiboken_header_filepath}")
        configure_file("${_output_dir}/side_config.txt.in" "${_output_dir}/side_config.txt" @ONLY)
        set(_side_config_file "${_output_dir}/side_config.txt")
    endif()

    set(_generator_dependencies "${args_GLUE_FILES}" "${CMAKE_CURRENT_SOURCE_DIR}/${_shiboken_header_filepath}"
                                "${CMAKE_CURRENT_SOURCE_DIR}/${_typesystem_filepath}")
    get_target_property(shiboken_bin ${DCC_SHIBOKEN_BIN_TARGET} LOCATION)
    if(WIN32)
        set(_qt_bin "${DCC_QT_INSTALL_PREFIX}/bin")
    else()
        set(_qt_bin "${DCC_QT_LIB_DIR}")
    endif()

    # Shiboken inherits neither the compiler flags nor the toolchain. Both options go into one --clang-options list,
    # because a second occurrence of the flag replaces the first: -include puts oneTBB's profiling header ahead of Qt's
    # emit macro, and -isysroot lets shiboken's clang find the SDK's C++ headers at all.
    set(_shiboken_clang_options "")
    if(TBB_INCLUDE_DIRS AND EXISTS "${TBB_INCLUDE_DIRS}/oneapi/tbb/profiling.h")
        list(APPEND _shiboken_clang_options "-include,${TBB_INCLUDE_DIRS}/oneapi/tbb/profiling.h")
    endif()
    if(APPLE)
        # shiboken parses with libclang from the LLVM keg, which does not know the SDK layout the way Apple's clang
        # does: without -isysroot it cannot find SDK headers such as TargetConditionals.h, and every header that
        # includes USD fails to parse. CMAKE_OSX_SYSROOT is often empty (clang's own default), so fall back to the
        # active developer directory.
        set(_shiboken_sysroot "${CMAKE_OSX_SYSROOT}")
        if(NOT _shiboken_sysroot OR _shiboken_sysroot STREQUAL "macosx")
            execute_process(
                COMMAND xcrun --show-sdk-path
                OUTPUT_VARIABLE _shiboken_sysroot
                ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
        endif()
        if(_shiboken_sysroot AND EXISTS "${_shiboken_sysroot}")
            list(APPEND _shiboken_clang_options "-isysroot,${_shiboken_sysroot}")
        endif()
    endif()
    set(_shiboken_clang_args "")
    if(_shiboken_clang_options)
        string(JOIN "," _shiboken_clang_option_list ${_shiboken_clang_options})
        set(_shiboken_clang_args "--clang-options=${_shiboken_clang_option_list}")
    endif()

    set(_shiboken_system_include_args "")
    if(_shiboken_system_includes)
        list(REMOVE_DUPLICATES _shiboken_system_includes)
        string(JOIN "${OS_ENV_SEPARATOR}" _shiboken_system_include_list ${_shiboken_system_includes})
        set(_shiboken_system_include_args "--system-include-paths=${_shiboken_system_include_list}")
    endif()

    add_custom_command(
        OUTPUT ${_headers} ${_sources}
        COMMAND
            ${CMAKE_COMMAND} -E env
            "${OS_LIBRARY_ENV_NAME}=${_qt_bin}${OS_ENV_SEPARATOR}${SHIBOKEN_CLANG_INSTALL_DIR}/bin${OS_ENV_SEPARATOR}$ENV{${OS_LIBRARY_ENV_NAME}}"
            "${shiboken_bin}" "--output-directory=${_output_dir}/wrap" ${_shiboken_clang_args}
            ${_shiboken_system_include_args} "--project-file=${_side_config_file}"
        DEPENDS ${_generator_dependencies})

    add_library(${TARGET_NAME} SHARED ${_headers} ${_sources} ${_generator_dependencies})

    set_target_properties(${TARGET_NAME} PROPERTIES PYSIDE_TYPESYSTEM_PATH "${_typesystem_generated}"
                                                    PYSIDE_SOURCES_DIR "${_output_dir}/wrap/${_src_path}")

    # Since we have no guarantees how #includes in generated file will be look like add source dir of dependent
    # typesystems to include paths, it also simplifies search for other module that will link with current target
    get_target_property(_target_source_dir ${args_TARGET} SOURCE_DIR)

    target_include_directories(
        ${TARGET_NAME}
        PUBLIC "${_target_source_dir}"
               "${_typesystem_includes}"
               "${PYTHON_INCLUDE_DIR}"
               "${PYSIDE_INCLUDE_DIR}"
               "${PYSIDE_INCLUDE_DIR}/QtCore"
               "${PYSIDE_INCLUDE_DIR}/QtWidgets"
               "${PYSIDE_INCLUDE_DIR}/QtGui")

    if(args_INCLUDE_DIRS)
        target_include_directories(${TARGET_NAME} PUBLIC "${args_INCLUDE_DIRS}")
    endif()
    target_link_libraries(
        ${TARGET_NAME}
        ${args_TARGET}
        ${DCC_SHIBOKEN_LIB_TARGET}
        ${DCC_PYSIDE_TARGET}
        pybind11::pybind11
        ${PYTHON_LIBRARY}
        ${_dependent_pyside_modules}
        ${args_LIBRARY_DEPENDENCIES})

    if(args_PRIVATE_DEFINITIONS)
        target_compile_definitions(${TARGET_NAME} PRIVATE ${args_PRIVATE_DEFINITIONS})
    endif()
    if(args_PUBLIC_DEFINITIONS)
        target_compile_definitions(${TARGET_NAME} PUBLIC ${args_PUBLIC_DEFINITIONS})
    endif()

    if(MSVC)
        set_target_properties(${TARGET_NAME} PROPERTIES SUFFIX ".pyd")
    else()
        set_target_properties(${TARGET_NAME} PROPERTIES SUFFIX ".so")
    endif()
    set_target_properties(${TARGET_NAME} PROPERTIES PREFIX "" OUTPUT_NAME ${_module_name})

    if(args_PYTHON_INSTALL_DIR)
        set(_python_install_dir "${args_PYTHON_INSTALL_DIR}")
    else()
        set(_python_install_dir "${DCC_PYTHON_INSTALL_SITE_PACKAGES_ROOT}/opendcc")
    endif()

    install(
        TARGETS ${TARGET_NAME}
        RUNTIME DESTINATION "${_python_install_dir}"
        LIBRARY DESTINATION "${_python_install_dir}")

    if(MSVC)
        install(
            FILES $<TARGET_PDB_FILE:${TARGET_NAME}>
            DESTINATION "${_python_install_dir}"
            OPTIONAL)
    endif()
    if(args_VS_FOLDER)
        make_folder("${args_VS_FOLDER}" ${TARGET_NAME})
    endif()
endfunction()
