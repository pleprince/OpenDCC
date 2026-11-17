The vendor folder contains small third-party libraries used in the opendcc.base module.
When upgrading a library, please update the commit hash or version tag in the description below.

**cli11**
https://github.com/CLIUtils/CLI11

**cpptoml**  
https://github.com/skystrife/cpptoml

**cppzmq**  
https://github.com/zeromq/cppzmq  
commit 160ac8ec61298508093933a9f53bfedfb6ba0425

**eventpp**  
https://github.com/wqking/eventpp  
commit a3f50689457c73f45da0e4e2d64cb80142d10958

**jsoncpp**  
https://github.com/open-source-parsers/jsoncpp 

**nonstd**  
https://github.com/martinmoene/any-lite

**tiny_process**  
https://gitlab.com/eidheim/tiny-process-library

**tsl**  
https://github.com/Tessil/robin-map

**vhacd**
https://github.com/bulletphysics/bullet3
extracted from `Extras/VHACD` of Bullet 3.25 (bullet3-3.25), license in `vhacd/LICENSE.txt`.
Bullet ships it without a CMake build file and the conda-forge `bullet-cpp` package does not
install it, so the sources that `opendcc.usd_editor.bullet_physics` needs for mesh convex
decomposition are vendored here.
