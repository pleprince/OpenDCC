// Copyright Contributors to the OpenDCC project
// SPDX-License-Identifier: Apache-2.0
//
// OpenImageIO 3.x includes <fmt/args.h> and friends from its public headers. The application already ships fmt as
// part of spdlog, and two fmt copies in one translation unit collide (both define namespace fmt when OIIO turns the
// inline namespace off). Forward to that single copy instead of adding another fmt to the include path.
#pragma once
#include <opendcc/base/vendor/spdlog/fmt/bundled/args.h>
