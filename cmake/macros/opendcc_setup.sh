# Assume script is sourced and located in the installation root.
# $_ is the previous command's last argument, not this file's path, so it cannot be used to locate the tree.
if [ -n "${BASH_SOURCE:-}" ]; then
    _opendcc_setup_src="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
    # zsh-only expansion, kept in eval so bash never parses it.
    eval '_opendcc_setup_src="${(%):-%x}"'
else
    _opendcc_setup_src="$0"
fi
export OPENDCC_ROOT="$(cd "$(dirname "${_opendcc_setup_src}")" && pwd -P)"
unset _opendcc_setup_src

# qt-plugins is optional: it is only populated when Qt plugins are bundled into the tree, otherwise Qt resolves its
# plugins from the Qt that the binaries link against.
if [[ ! -d "${OPENDCC_ROOT}/plugin" || \
          ! -d "${OPENDCC_ROOT}/bin" ||
          ! -d "${OPENDCC_ROOT}/lib" ]]; then
    echo "ERROR: current directory is not a OpenDCC installation. Cannot continue."
    unset OPENDCC_ROOT
else
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # dyld ignores LD_LIBRARY_PATH and reads DYLD_FALLBACK_LIBRARY_PATH when an @rpath reference misses.
        export DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH:$OPENDCC_ROOT/lib:$OPENDCC_ROOT/plugin/opendcc:$OPENDCC_ROOT/plugin/usd"
    else
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$OPENDCC_ROOT/lib:$OPENDCC_ROOT/plugin/opendcc:$OPENDCC_ROOT/plugin/usd:$OPENDCC_ROOT"
    fi
    export PATH="$OPENDCC_ROOT/bin:$PATH"
    #used to fix OCIO parsing bug on non english-locales
    export LC_NUMERIC=C
fi
