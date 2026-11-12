#!/bin/bash
# POSIX counterpart of opendcc.bat: prepare the runtime environment and forward every argument to the application, so
# `opendcc --script file.py` behaves exactly like `bin/dcc_base --script file.py` started with the environment set up.

# Resolve this script through symlinks so a link on PATH still finds the tree it points into.
self="$0"
while [ -h "$self" ]; do
    directory="$(cd -P "$(dirname "$self")" && pwd)"
    link="$(readlink "$self")"
    case "$link" in
        /*) self="$link" ;;
        *) self="$directory/$link" ;;
    esac
done
APP_DIR="$(cd -P "$(dirname "$self")" && pwd)"

# One definition of the runtime environment, shared with an interactive shell that sources the same file.
if [ -f "${APP_DIR}/opendcc_setup.sh" ]; then
    . "${APP_DIR}/opendcc_setup.sh"
fi

# The application ships its own interpreter packages (pxr, PySide6, opendcc). A foreign USD or PySide install on
# PYTHONPATH would shadow them and fail on ABI mismatch (pxr from another USD build, another interpreter), so those
# entries are dropped rather than merely ranked lower: USD imports its modules by name at runtime and resolves them
# against the whole path.
app_site_packages=""
for site_packages in "${APP_DIR}"/lib/python*/site-packages; do
    if [ -d "${site_packages}" ]; then
        app_site_packages="${site_packages}"
        break
    fi
done

if [ -n "${app_site_packages}" ]; then
    filtered=""
    IFS=':' read -r -a path_entries <<< "${PYTHONPATH:-}"
    for entry in "${path_entries[@]}"; do
        [ -z "${entry}" ] && continue
        [ "${entry}" = "${app_site_packages}" ] && continue
        if [ -d "${entry}/pxr" ] || [ -d "${entry}/PySide6" ]; then
            continue
        fi
        filtered="${filtered:+${filtered}:}${entry}"
    done
    export PYTHONPATH="${app_site_packages}${filtered:+:${filtered}}"
fi

exec "${APP_DIR}/bin/dcc_base" "$@"
