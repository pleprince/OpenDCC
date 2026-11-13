# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
#
# Expands USD's codegen plugInfo.json template for a schema whose schema.usda declares no classes: usdGenSchema
# writes no plugInfo.json in that case, and the plugin still needs one. The template ships with USD itself, so the
# caller passes the path it found:
#
#   cmake -DPLUG_INFO_TEMPLATE=<...>/codegenTemplates/plugInfo.json -DLIBRARY_NAME=<name>
#         -DOUTPUT=<file> -P generate_empty_plug_info.cmake
#
# The template's only substitution is the jinja2 placeholder {{ libraryName }}.

foreach(_required PLUG_INFO_TEMPLATE LIBRARY_NAME OUTPUT)
    if(NOT DEFINED ${_required})
        message(FATAL_ERROR "generate_empty_plug_info.cmake requires -D${_required}=...")
    endif()
endforeach()

if(NOT EXISTS "${PLUG_INFO_TEMPLATE}")
    message(FATAL_ERROR "plugInfo.json template not found at ${PLUG_INFO_TEMPLATE}")
endif()

file(READ "${PLUG_INFO_TEMPLATE}" _content)
string(REPLACE "{{ libraryName }}" "${LIBRARY_NAME}" _content "${_content}")
if(_content MATCHES "\\{\\{")
    # A template that grew another placeholder is not something this expansion can honour silently.
    message(FATAL_ERROR "${PLUG_INFO_TEMPLATE} has a placeholder besides {{ libraryName }}")
endif()
# The previous jinja2 expansion dropped the template's final newline; keep the bytes identical so an already
# generated plugin resource does not change.
string(REGEX REPLACE "\n$" "" _content "${_content}")

file(WRITE "${OUTPUT}" "${_content}")
