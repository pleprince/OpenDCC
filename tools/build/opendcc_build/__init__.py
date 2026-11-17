# Copyright Contributors to the OpenDCC project
# SPDX-License-Identifier: Apache-2.0
"""pixi-driven build system for OpenDCC.

Layout of the pieces:

  VERSIONS.md              dependency versions and OpenUSD releases, parsed by versions.py
  pixi.toml                the "tools" environment: python, cmake, ninja, git
  tools/build/opendcc-build  entry point used by pixi tasks

Every opendcc build gets a derived pixi environment under build/<slug>/env, pinned from either
a VERSIONS.md release row (build OpenUSD from source) or a probed OpenUSD installation (build
against it). Nothing in this package pins a version on its own.
"""

__all__ = ["cli"]
