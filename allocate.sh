#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_BOOTSTRAP_URL="https://raw.githubusercontent.com/instantomics/bootstrap/main/bootstrap.sh"

die() {
    printf 'allocate: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing prerequisite: $1"
}

account="${BOOTSTRAP_ACCOUNT:-${SLURM_ACCOUNT:-wouter_saelens}}"
time_limit="${BOOTSTRAP_TIME:-${SLURM_TIME:-14-00:00:00}}"
partition="${BOOTSTRAP_PARTITION:-${SLURM_PARTITION:-}}"
nodes="${BOOTSTRAP_NODES:-${SLURM_NNODES:-${SLURM_NODES:-}}}"
ntasks="${BOOTSTRAP_NTASKS:-${SLURM_NTASKS:-}}"
cpus_per_task="${BOOTSTRAP_CPUS_PER_TASK:-${SLURM_CPUS_PER_TASK:-}}"
memory="${BOOTSTRAP_MEM:-${SLURM_MEM:-${SLURM_MEM_PER_NODE:-}}}"
gres="${BOOTSTRAP_GRES:-${SLURM_GRES:-}}"
constraint="${BOOTSTRAP_CONSTRAINT:-${SLURM_CONSTRAINT:-}}"
bootstrap_url="${BOOTSTRAP_URL:-$DEFAULT_BOOTSTRAP_URL}"

require_command curl

run_bootstrap() {
    curl --fail --silent --show-error --location \
        --connect-timeout "${BOOTSTRAP_CURL_CONNECT_TIMEOUT:-10}" \
        --max-time "${BOOTSTRAP_CURL_MAX_TIME:-120}" \
        -- "$bootstrap_url" | bash -s -- "$@"
}

# An existing allocation is already the required execution boundary.
if [[ -n ${SLURM_JOB_ID:-} ]]; then
    run_bootstrap "$@"
    exit $?
fi

require_command srun

srun_args=(--pty "--account=$account" "--time=$time_limit")
[[ -n $partition ]] && srun_args+=("--partition=$partition")
[[ -n $nodes ]] && srun_args+=("--nodes=$nodes")
[[ -n $ntasks ]] && srun_args+=("--ntasks=$ntasks")
[[ -n $cpus_per_task ]] && srun_args+=("--cpus-per-task=$cpus_per_task")
[[ -n $memory ]] && srun_args+=("--mem=$memory")
[[ -n $gres ]] && srun_args+=("--gres=$gres")
[[ -n $constraint ]] && srun_args+=("--constraint=$constraint")

if [[ -n ${BOOTSTRAP_EXTRA_SRUN_ARGS:-} ]]; then
    extra_srun_args=()
    read -r -a extra_srun_args <<< "$BOOTSTRAP_EXTRA_SRUN_ARGS"
    srun_args+=("${extra_srun_args[@]}")
fi

remote_bootstrap='set -euo pipefail
curl --fail --silent --show-error --location \
    --connect-timeout "${BOOTSTRAP_CURL_CONNECT_TIMEOUT:-10}" \
    --max-time "${BOOTSTRAP_CURL_MAX_TIME:-120}" \
    -- "$1" | bash -s -- "${@:2}"'

exec srun "${srun_args[@]}" -- bash -c "$remote_bootstrap" bootstrap "$bootstrap_url" "$@"
