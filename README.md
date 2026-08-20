# Iomix Contributor Bootstrap

This public phase-zero repository has one deliberately small path from a clean
shell to a source-author workspace. It intentionally follows `main`: the
allocation script fetches the current `bootstrap.sh`, and that script installs
the current `iom` `main` over authenticated SSH. No release or commit is pinned.

Run this exact one-liner outside in the login node on SLURM:

```bash
curl -fsSL https://raw.githubusercontent.com/instantomics/bootstrap/main/allocate.sh | bash -s --
```

The two steps are direct:

1. `allocate.sh` starts one interactive `srun --pty` job with a 14-day default,
   then fetches and runs current-main `bootstrap.sh` inside that job.
2. `bootstrap.sh` validates the SLURM allocation and `SCRATCHDIR`, prompts on
   `/dev/tty` for a persistent workspace (defaulting to the current directory),
   installs `iom`, runs `iom workspace bootstrap --role source-author
   --workspace PATH`, and runs `iom workspace doctor` from that workspace.

The workspace must be outside `SCRATCHDIR`; `iom` owns and rejects that
placement check. On success the script enters an interactive login shell in the
workspace and keeps the allocation open. It does not submit a smoke job.

For a non-interactive bootstrap, pass the workspace explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/instantomics/bootstrap/main/bootstrap.sh | bash -s -- --workspace /persistent/path
```

That direct form still requires an existing SLURM allocation and an absolute,
existing, writable `SCRATCHDIR`.

## Allocation Overrides

The defaults are account `wouter_saelens`, time `14-00:00:00`, and no
partition. Set these non-secret environment variables before the one-liner when
the site needs different resources:

- `BOOTSTRAP_ACCOUNT`
- `BOOTSTRAP_TIME`
- `BOOTSTRAP_PARTITION`
- `BOOTSTRAP_NODES`
- `BOOTSTRAP_NTASKS`
- `BOOTSTRAP_CPUS_PER_TASK`
- `BOOTSTRAP_MEM`
- `BOOTSTRAP_GRES`
- `BOOTSTRAP_CONSTRAINT`
- `BOOTSTRAP_EXTRA_SRUN_ARGS` for additional whitespace-separated `srun` flags

The scripts never print the environment or credential material. GitHub SSH
authentication must already be available to the allocation for the `iom` Git
install.

## Prerequisites

The host needs Bash, `curl`, and Slurm `srun`. The allocation needs `uv`, Git,
GitHub CLI, SSH, and the GNU `timeout` command. `iom` creates or reuses the
workspace and performs its own contributor checks.

All uv tool, binary, Python, cache, and XDG cache paths used by the bootstrap
are placed below `SCRATCHDIR` and are disposable with the allocation.

## Tests

Run the dependency-free shell harness with:

```bash
bash -n allocate.sh bootstrap.sh tests/test.sh
bash tests/test.sh
```
