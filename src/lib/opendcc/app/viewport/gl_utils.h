// Copyright Contributors to the OpenDCC project
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include "opendcc/opendcc.h"
#include <pxr/pxr.h>
#if PXR_VERSION < 2108
#include <GL/glew.h>
#else
#include <pxr/imaging/garch/glApi.h>
#endif

OPENDCC_NAMESPACE_OPEN

namespace gl_utils
{
    /**
     * GL debug groups (glPushDebugGroup/glPopDebugGroup, GL_DEBUG_SOURCE_*) were added in OpenGL 4.3. Apple's OpenGL
     * implementation stops at 4.1, so on macOS USD's GL function table has no entry for them and calling through it
     * jumps to a null pointer. Every call site checks this first.
     */
    inline bool debug_groups_available()
    {
#if defined(ARCH_OS_DARWIN)
        return false;
#else
        return true;
#endif
    }
}

OPENDCC_NAMESPACE_CLOSE