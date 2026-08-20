#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_BIN="$TEST_ROOT/bin"
SCRATCH="$TEST_ROOT/scratch"
ALLOCATION_TMP="$TEST_ROOT/allocation-tmp"
HOME_ROOT="$TEST_ROOT/home"
mkdir -p "$FAKE_BIN" "$SCRATCH" "$ALLOCATION_TMP" "$HOME_ROOT"

export PATH="$FAKE_BIN:$PATH"
export SCRATCHDIR="$SCRATCH"
export TMPDIR="$ALLOCATION_TMP"
export HOME="$HOME_ROOT"
export SLURM_JOB_ID=fake-job
export FAKE_CURL_PAYLOAD="$ROOT/bootstrap.sh"
export FAKE_CURL_LOG="$TEST_ROOT/curl.log"
export FAKE_SRUN_LOG="$TEST_ROOT/srun.log"
export FAKE_UV_LOG="$TEST_ROOT/uv.log"
export FAKE_IOM_LOG="$TEST_ROOT/iom.log"
export BOOTSTRAP_NO_SHELL=1

cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'curl'
    printf ' %q' "$@"
    printf '\n'
} >>"$FAKE_CURL_LOG"
cat "$FAKE_CURL_PAYLOAD"
EOF

cat >"$FAKE_BIN/srun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'srun'
    printf ' %q' "$@"
    printf '\n'
} >>"$FAKE_SRUN_LOG"
while (($# > 0)); do
    case "$1" in
        --)
            shift
            break
            ;;
        --pty|--account=*|--time=*|--partition=*|--nodes=*|--ntasks=*|\
        --cpus-per-task=*|--mem=*|--gres=*|--constraint=*)
            shift
            ;;
        *)
            printf 'unexpected fake srun option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done
SLURM_JOB_ID=fake-job exec "$@"
EOF

cat >"$FAKE_BIN/uv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'UV_TOOL_DIR=%s\n' "$UV_TOOL_DIR"
    printf 'UV_TOOL_BIN_DIR=%s\n' "$UV_TOOL_BIN_DIR"
    printf 'UV_CACHE_DIR=%s\n' "$UV_CACHE_DIR"
    printf 'UV_PYTHON_INSTALL_DIR=%s\n' "$UV_PYTHON_INSTALL_DIR"
    printf 'XDG_CACHE_HOME=%s\n' "$XDG_CACHE_HOME"
    printf 'args:'
    printf ' %q' "$@"
    printf '\n'
} >>"$FAKE_UV_LOG"
EOF

cat >"$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$FAKE_BIN/iom" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'cwd=%s args:' "$PWD"
    printf ' %s' "$@"
    printf '\n'
    printf 'IOM_CACHE_ROOT=%s\n' "$IOM_CACHE_ROOT"
} >>"$FAKE_IOM_LOG"

if [[ ${1:-} == workspace && ${2:-} == bootstrap ]]; then
    workspace=
    while (($# > 0)); do
        if [[ $1 == --workspace ]]; then
            (($# >= 2)) || exit 2
            workspace=$2
            break
        fi
        shift
    done
    if [[ ${FAKE_IOM_REJECT_SCRATCH:-0} == 1 && \
        ("$workspace" == "$SCRATCHDIR" || "$workspace" == "$SCRATCHDIR"/*) ]]; then
        exit 1
    fi
    mkdir -p "$workspace"
fi
EOF

chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/srun" "$FAKE_BIN/uv" "$FAKE_BIN/gh" \
    "$FAKE_BIN/iom"

export FAKE_ARGUMENT_LOG="$TEST_ROOT/arguments.log"
cat >"$TEST_ROOT/argument-payload.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'argc=%s' "$#" >>"$FAKE_ARGUMENT_LOG"
printf ' arg=<%s>' "$@" >>"$FAKE_ARGUMENT_LOG"
printf '\n' >>"$FAKE_ARGUMENT_LOG"
EOF
chmod +x "$TEST_ROOT/argument-payload.sh"

assert_file_contains() {
    local file=$1
    local pattern=$2
    grep -F -- "$pattern" "$file" >/dev/null || {
        printf 'missing %s in %s\n' "$pattern" "$file" >&2
        exit 1
    }
}

assert_file_lacks() {
    local file=$1
    local pattern=$2
    if grep -F -- "$pattern" "$file" >/dev/null; then
        printf 'unexpected %s in %s\n' "$pattern" "$file" >&2
        exit 1
    fi
}

assert_not_file() {
    [[ ! -e $1 ]] || {
        printf 'unexpected file: %s\n' "$1" >&2
        exit 1
    }
}

run_bootstrap() {
    : >"$FAKE_IOM_LOG"
    env -u FAKE_IOM_REJECT_SCRATCH "$ROOT/bootstrap.sh" --workspace "$1"
}

rm -f "$FAKE_ARGUMENT_LOG"
FAKE_CURL_PAYLOAD="$TEST_ROOT/argument-payload.sh" env -u SLURM_JOB_ID \
    "$ROOT/allocate.sh" first "two words" ""
assert_file_contains "$FAKE_ARGUMENT_LOG" 'argc=3 arg=<first> arg=<two words> arg=<>'

workspace="$TEST_ROOT/persistent workspace"
rm -f "$FAKE_SRUN_LOG" "$FAKE_IOM_LOG"
env -u SLURM_JOB_ID \
    BOOTSTRAP_URL="https://example.invalid/bootstrap.sh" \
    "$ROOT/allocate.sh" --workspace "$workspace"
assert_file_contains "$FAKE_SRUN_LOG" '--time=14-00:00:00'
assert_file_contains "$FAKE_SRUN_LOG" '--account=wouter_saelens'
assert_file_lacks "$FAKE_SRUN_LOG" '--partition='
assert_file_contains "$FAKE_IOM_LOG" "args: workspace bootstrap --role source-author --workspace $workspace"
assert_file_contains "$FAKE_IOM_LOG" "args: workspace doctor"
assert_file_contains "$FAKE_IOM_LOG" "cwd=$workspace args: workspace doctor"
assert_file_contains "$FAKE_IOM_LOG" "IOM_CACHE_ROOT=$HOME_ROOT/.local/state/iom"

rm -f "$FAKE_SRUN_LOG"
export BOOTSTRAP_TIME=02:00:00
export BOOTSTRAP_ACCOUNT=test_account
export BOOTSTRAP_PARTITION=test_partition
"$ROOT/allocate.sh" --workspace "$TEST_ROOT/reused"
assert_not_file "$FAKE_SRUN_LOG"
unset BOOTSTRAP_TIME BOOTSTRAP_ACCOUNT BOOTSTRAP_PARTITION

: >"$FAKE_UV_LOG"
run_bootstrap "$TEST_ROOT/allocation-local"
assert_file_contains "$FAKE_UV_LOG" "UV_TOOL_DIR=$SCRATCH/uv/tools"
assert_file_contains "$FAKE_UV_LOG" "UV_TOOL_BIN_DIR=$SCRATCH/uv/bin"
assert_file_contains "$FAKE_UV_LOG" "UV_CACHE_DIR=$SCRATCH/uv/cache"
assert_file_contains "$FAKE_UV_LOG" "UV_PYTHON_INSTALL_DIR=$SCRATCH/uv/python"
assert_file_contains "$FAKE_UV_LOG" "XDG_CACHE_HOME=$SCRATCH/uv/xdg-cache"
if grep -E "UV_(TOOL|CACHE|PYTHON)|XDG_CACHE_HOME" "$FAKE_UV_LOG" | grep -vF "$SCRATCH/" >/dev/null; then
    printf 'uv state escaped SCRATCHDIR\n' >&2
    exit 1
fi

: >"$FAKE_IOM_LOG"
explicit_state="$TEST_ROOT/explicit-state"
IOM_CACHE_ROOT="$explicit_state" run_bootstrap "$TEST_ROOT/explicit-cache"
assert_file_contains "$FAKE_IOM_LOG" "IOM_CACHE_ROOT=$explicit_state"

if IOM_CACHE_ROOT="$SCRATCH/state" "$ROOT/bootstrap.sh" --workspace "$TEST_ROOT/bad-cache" \
    >"$TEST_ROOT/bad-cache.out" 2>&1; then
    printf 'bootstrap unexpectedly accepted scratch-backed Iom state\n' >&2
    exit 1
fi
assert_file_contains "$TEST_ROOT/bad-cache.out" 'IOM_CACHE_ROOT must remain outside SCRATCHDIR'

rm -f "$FAKE_IOM_LOG"
if "$ROOT/bootstrap.sh" </dev/null >"$TEST_ROOT/no-tty.out" 2>&1; then
    printf 'bootstrap unexpectedly accepted a missing workspace without a TTY\n' >&2
    exit 1
fi
assert_file_contains "$TEST_ROOT/no-tty.out" '--workspace PATH is required when no TTY is available'
assert_not_file "$FAKE_IOM_LOG"

: >"$FAKE_IOM_LOG"
if FAKE_IOM_REJECT_SCRATCH=1 "$ROOT/bootstrap.sh" --workspace "$SCRATCH/rejected" >"$TEST_ROOT/rejected.out" 2>&1; then
    printf 'bootstrap unexpectedly accepted a SCRATCHDIR workspace\n' >&2
    exit 1
fi
assert_file_contains "$FAKE_IOM_LOG" "args: workspace bootstrap --role source-author --workspace $SCRATCH/rejected"
if grep -F 'args: workspace doctor' "$FAKE_IOM_LOG" >/dev/null; then
    printf 'doctor ran after iom rejected the workspace\n' >&2
    exit 1
fi
if grep -F 'Workspace ready:' "$TEST_ROOT/rejected.out" >/dev/null; then
    printf 'bootstrap printed success after iom rejected the workspace\n' >&2
    exit 1
fi

printf 'shell tests passed\n'
