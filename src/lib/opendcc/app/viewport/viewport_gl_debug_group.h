// Copyright Contributors to the OpenDCC project
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include "opendcc/opendcc.h"

#include <pxr/pxr.h>
#include <pxr/imaging/garch/glApi.h>

OPENDCC_NAMESPACE_OPEN

/// Scoped GL debug annotation ("ViewportGrid", "Compositor", ...).
///
/// glPushDebugGroup/glPopDebugGroup are OpenGL 4.3 entry points. The API loader leaves them null
/// on a context that does not provide them -- macOS stops at OpenGL 4.1 -- so calling them
/// unconditionally jumps to address 0. This guard turns them into a no-op there.
class GLScopedDebugGroup
{
public:
    GLScopedDebugGroup(GLenum source, GLuint id, const char* message)
        : m_active(glPushDebugGroup != nullptr && glPopDebugGroup != nullptr)
    {
        if (m_active)
            glPushDebugGroup(source, id, -1, message);
    }

    GLScopedDebugGroup(const GLScopedDebugGroup&) = delete;
    GLScopedDebugGroup& operator=(const GLScopedDebugGroup&) = delete;

    ~GLScopedDebugGroup()
    {
        if (m_active)
            glPopDebugGroup();
    }

private:
    bool m_active;
};

OPENDCC_NAMESPACE_CLOSE
