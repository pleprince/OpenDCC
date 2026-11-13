function(setup_update_translations OUT_VAR)
    set(_i18n_dir "${CMAKE_SOURCE_DIR}/i18n")

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

    # The tool wrappers need the Qt and PySide binaries on the library path; both live outside the install prefix.
    set(_tool_environment
        "${OS_LIBRARY_ENV_NAME}=${Qt_PATH}${OS_ENV_SEPARATOR}${pyside_dir}${OS_ENV_SEPARATOR}$ENV{${OS_LIBRARY_ENV_NAME}}")

    # DCC_LANG=all maintains every catalogue but ships the English one, which is what the application falls back to.
    if(DCC_LANG STREQUAL "all")
        set(_maintained_langs ru en)
        set(_built_langs en)
    else()
        set(_maintained_langs "${DCC_LANG}")
        set(_built_langs "${DCC_LANG}")
    endif()

    set(ts_files "")
    foreach(_lang IN LISTS _maintained_langs)
        list(APPEND ts_files "${_i18n_dir}/i18n.${_lang}.ts")
    endforeach()
    # One lupdate run covers every maintained catalogue: it takes one -ts output per language.
    add_custom_target(
        update_translations
        COMMAND
            ${CMAKE_COMMAND} -E env "${_tool_environment}" "${Qt_PATH}/bin/lupdate" -extensions
            "h,hpp,c,cpp,c++,cxx,py" "${CMAKE_SOURCE_DIR}/src" -tr-function-alias "translate+=i18n" -ts ${ts_files}
    )

    # QTranslator fails a whole catalogue if one of its declared dependencies is missing, so Qt's own translations
    # are chained in through a loader catalogue only when that .qm exists. The loader is written at configure time
    # and kept: it is a build input, so removing it after lrelease would leave the next build without the chain.
    set(qm_files "")
    foreach(_lang IN LISTS _built_langs)
        set(_ts_file "${_i18n_dir}/i18n.${_lang}.ts")
        set(_qm_file "${CMAKE_CURRENT_BINARY_DIR}/i18n/i18n.${_lang}.qm")
        set(_lrelease_inputs "${_ts_file}")
        if(EXISTS "${DCC_QT_INSTALL_PREFIX}/translations/qt_${_lang}.qm")
            set(_loader_file "${CMAKE_CURRENT_BINARY_DIR}/i18n/loader.${_lang}.ts")
            file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/i18n")
            file(WRITE "${_loader_file}"
                 "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                 "<!DOCTYPE TS>\n"
                 "<TS version=\"2.1\" language=\"${_lang}\">\n"
                 "    <dependencies>\n"
                 "        <dependency catalog=\"qt_${_lang}\"/>\n"
                 "    </dependencies>\n"
                 "</TS>\n")
            list(APPEND _lrelease_inputs "${_loader_file}")
        endif()
        add_custom_command(
            OUTPUT "${_qm_file}"
            DEPENDS ${_lrelease_inputs}
            COMMAND ${CMAKE_COMMAND} -E env "${_tool_environment}" "${DCC_QT_INSTALL_PREFIX}/bin/lrelease"
                    ${_lrelease_inputs} -qm "${_qm_file}")
        list(APPEND qm_files "${_qm_file}")
    endforeach()

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
