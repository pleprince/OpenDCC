function(setup_update_translations OUT_VAR)
    set(ts_files "${CMAKE_SOURCE_DIR}/i18n/i18n.en.ts")

    # Homebrew ships lupdate/lrelease in the qttools keg, not next to QtCore, and the macOS Qt root derived from the
    # framework binary is not the install prefix. Ask the imported tool where it lives.
    set(Qt_PATH "${DCC_QT_INSTALL_PREFIX}/bin")
    if(APPLE AND TARGET Qt${QT_VERSION_MAJOR}::lupdate)
        get_target_property(_lupdate_loc Qt${QT_VERSION_MAJOR}::lupdate IMPORTED_LOCATION_RELEASE)
        if(NOT _lupdate_loc)
            get_target_property(_lupdate_loc Qt${QT_VERSION_MAJOR}::lupdate IMPORTED_LOCATION)
        endif()
        if(_lupdate_loc)
            get_filename_component(_lupdate_bin_dir "${_lupdate_loc}" DIRECTORY)
            get_filename_component(Qt_PATH "${_lupdate_bin_dir}" DIRECTORY)
        endif()
    endif()

    get_target_property(pyside_dir ${DCC_SHIBOKEN_BIN_TARGET} IMPORTED_LOCATION_RELEASE)
    if(NOT pyside_dir)
        get_target_property(pyside_dir ${DCC_SHIBOKEN_BIN_TARGET} IMPORTED_LOCATION_RELWITHDEBINFO)
    endif()
    get_filename_component(pyside_dir ${pyside_dir} DIRECTORY)

    add_custom_target(
        update_translations
        DEPENDS "${CMAKE_SOURCE_DIR}/cmake/macros/make_i18n.py"
        COMMAND
            ${CMAKE_COMMAND} -E env
            "${OS_LIBRARY_ENV_NAME}=${Qt_PATH}${OS_ENV_SEPARATOR}${pyside_dir}${OS_ENV_SEPARATOR}$ENV{${OS_LIBRARY_ENV_NAME}}"
            "${PYTHON_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/cmake/macros/make_i18n.py" make_ts --src_dir
            "${CMAKE_SOURCE_DIR}/src" --output_dir "${CMAKE_SOURCE_DIR}/i18n" --qt_path "${DCC_QT_INSTALL_PREFIX}"
            --lang ${DCC_LANG})

    if(${DCC_LANG} STREQUAL "all")
        set(qm_files "${CMAKE_CURRENT_BINARY_DIR}/i18n/i18n.en.qm")
    else()
        set(qm_files "${CMAKE_CURRENT_BINARY_DIR}/i18n/i18n.${DCC_LANG}.qm")
    endif()

    add_custom_command(
        OUTPUT ${qm_files}
        DEPENDS ${ts_files} "${CMAKE_SOURCE_DIR}/cmake/macros/make_i18n.py"
        COMMAND
            ${CMAKE_COMMAND} -E env
            "${OS_LIBRARY_ENV_NAME}=${Qt_PATH}${OS_ENV_SEPARATOR}${pyside_dir}${OS_ENV_SEPARATOR}$ENV{${OS_LIBRARY_ENV_NAME}}"
            "${PYTHON_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/cmake/macros/make_i18n.py" make_qm --qt_path
            "${DCC_QT_INSTALL_PREFIX}" --inputs ${ts_files} --output_dir "${CMAKE_CURRENT_BINARY_DIR}/i18n")

    install(FILES ${qm_files} DESTINATION i18n)

    foreach(_f ${qm_files})
        string(REGEX MATCHALL "^.*\\.(.*)\\.qm$" _ ${_f})
        file(
            GLOB _qt_qms
            LIST_DIRECTORIES false
            "${DCC_QT_INSTALL_PREFIX}/translations/qt*_${CMAKE_MATCH_1}.qm")
        set(_lang ${CMAKE_MATCH_1})
        # install(FILES) on a missing file is a hard error, and which .qm files a Qt ships varies. Install only the
        # catalogues this one has.
        set(_qt_qm_candidates
            "${DCC_QT_INSTALL_PREFIX}/translations/qt_${_lang}.qm"
            "${DCC_QT_INSTALL_PREFIX}/translations/qtbase_${_lang}.qm"
            "${DCC_QT_INSTALL_PREFIX}/translations/qtscript_${_lang}.qm"
            "${DCC_QT_INSTALL_PREFIX}/translations/qtmultimedia_${_lang}.qm"
            "${DCC_QT_INSTALL_PREFIX}/translations/qtxmlpatterns_${_lang}.qm")
        set(_qt_qm_present)
        foreach(_qm ${_qt_qm_candidates})
            if(EXISTS "${_qm}")
                list(APPEND _qt_qm_present "${_qm}")
            endif()
        endforeach()
        if(_qt_qm_present)
            install(FILES ${_qt_qm_present} DESTINATION i18n)
        endif()
    endforeach()

    # Return qm_files to caller
    set(${OUT_VAR}
        ${qm_files}
        PARENT_SCOPE)
endfunction()
