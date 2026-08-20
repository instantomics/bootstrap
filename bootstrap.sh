#!/usr/bin/env bash
set -euo pipefail

umask 007

readonly IOM_SOURCE="git+ssh://git@github.com/instantomics/iom.git@main"

die() {
    printf 'bootstrap: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing prerequisite: $1"
}

usage() {
    printf 'Usage: bootstrap.sh [--workspace PATH]\n'
}

workspace=
workspace_given=0
while (($# > 0)); do
    case "$1" in
        --workspace)
            (($# >= 2)) || die "--workspace requires PATH"
            workspace=$2
            workspace_given=1
            shift 2
            ;;
        --workspace=*)
            workspace=${1#*=}
            workspace_given=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "unsupported argument: $1"
            ;;
    esac
done

[[ -n ${SLURM_JOB_ID:-} ]] || die "must run inside a SLURM allocation"

scratchdir=${SCRATCHDIR:-}
if [[ -z $scratchdir || $scratchdir != /* || ! -d $scratchdir || ! -w $scratchdir || ! -x $scratchdir ]]; then
    die "SCRATCHDIR must be an absolute existing writable directory"
fi

tmpdir=${TMPDIR:-}
if [[ -z $tmpdir || $tmpdir != /* || ! -d $tmpdir || ! -w $tmpdir || ! -x $tmpdir ]]; then
    die "TMPDIR must be an absolute existing writable and executable directory"
fi

: "${HOME:?bootstrap: HOME is required}"
export IOM_CACHE_ROOT=${IOM_CACHE_ROOT:-"$HOME/.local/state/iom"}
[[ $IOM_CACHE_ROOT == /* ]] || die "IOM_CACHE_ROOT must be absolute"
mkdir -p "$IOM_CACHE_ROOT"
scratch_real=$(cd -- "$scratchdir" && pwd -P)
cache_real=$(cd -- "$IOM_CACHE_ROOT" && pwd -P)
if [[ $cache_real == "$scratch_real" || $cache_real == "$scratch_real"/* ]]; then
    die "IOM_CACHE_ROOT must remain outside SCRATCHDIR"
fi

if ((workspace_given == 0)); then
    if exec 3<>/dev/tty 2>/dev/null; then
        current_directory=$(pwd -P)
        printf 'Persistent workspace [%s]: ' "$current_directory" >&3
        if IFS= read -r workspace <&3; then
            :
        else
            workspace=
        fi
        exec 3>&-
        workspace=${workspace:-$current_directory}
    else
        die "--workspace PATH is required when no TTY is available"
    fi
fi

[[ -n $workspace ]] || die "--workspace requires PATH"

for command in gh git ssh timeout uv; do
    require_command "$command"
done

uv_root="$scratchdir/uv"
export UV_TOOL_DIR="$uv_root/tools"
export UV_TOOL_BIN_DIR="$uv_root/bin"
export UV_CACHE_DIR="$uv_root/cache"
export UV_PYTHON_INSTALL_DIR="$uv_root/python"
export XDG_CACHE_HOME="$uv_root/xdg-cache"
mkdir -p "$UV_TOOL_DIR" "$UV_TOOL_BIN_DIR" "$UV_CACHE_DIR" \
    "$UV_PYTHON_INSTALL_DIR" "$XDG_CACHE_HOME"
export PATH="$UV_TOOL_BIN_DIR:$PATH"

install_timeout="${BOOTSTRAP_IOM_INSTALL_TIMEOUT:-300}"
if ! timeout --foreground "$install_timeout" uv tool install --force --from "$IOM_SOURCE" iom; then
    die "could not install iom from main over SSH"
fi
hash -r
require_command iom

bootstrap_timeout="${BOOTSTRAP_WORKSPACE_TIMEOUT:-1800}"
doctor_timeout="${BOOTSTRAP_DOCTOR_TIMEOUT:-300}"
timeout --foreground "$bootstrap_timeout" \
    iom workspace bootstrap --role source-author --workspace "$workspace"
if ! (cd -- "$workspace" && timeout --foreground "$doctor_timeout" iom workspace doctor); then
    die "workspace doctor failed"
fi

cd -- "$workspace"
printf 'Workspace ready: %s\n' "$PWD"
if [[ ${BOOTSTRAP_NO_SHELL:-0} != 1 && -r /dev/tty && -w /dev/tty ]]; then
    exec "${SHELL:-/bin/bash}" -il </dev/tty >/dev/tty 2>&1
fi
