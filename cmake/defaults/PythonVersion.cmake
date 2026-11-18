# Refuse to configure against a different Python than the plan resolved.
#
# `pixi run plan` decides the interpreter (VERSIONS.md, a VFX platform year, or --python) and
# writes it into the CMake cache together with Python3_EXECUTABLE. Configuring with another one
# builds shiboken bindings for one interpreter while the application embeds another, and the
# python packages pixi installed (numpy, PySide6, ...) were built for the plan's one.
function(dcc_require_python_version)
    if(NOT DCC_EXPECTED_PYTHON_VERSION)
        return()
    endif()
    if(NOT DEFINED Python3_VERSION_MAJOR OR NOT DEFINED Python3_VERSION_MINOR)
        return()
    endif()
    string(REGEX MATCH "^[0-9]+\\.[0-9]+" _expected "${DCC_EXPECTED_PYTHON_VERSION}")
    set(_found "${Python3_VERSION_MAJOR}.${Python3_VERSION_MINOR}")
    if(NOT "${_expected}" STREQUAL "${_found}")
        message(
            FATAL_ERROR
                "OpenDCC is planned for Python ${DCC_EXPECTED_PYTHON_VERSION}, but CMake found Python ${_found} (${Python3_EXECUTABLE}).\n"
                "Configure from the plan instead: `pixi run plan -- <target>` then `pixi run configure`, which pass Python3_EXECUTABLE and DCC_EXPECTED_PYTHON_VERSION. To change the interpreter, replan with --python <version>."
        )
    endif()
endfunction()
