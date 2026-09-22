# Instantomics Bootstrap

## GitHub Setup

Install the [GitHub CLI](https://cli.github.com/) if `gh --version` is not
available, then authenticate GitHub using SSH:

```bash
gh auth login --hostname github.com --git-protocol ssh --web
gh auth status
ssh -T git@github.com
```

You must be an active member of the `instantomics` GitHub organization and have
access to its private repositories. Ask a project administrator if authentication
succeeds but repository access is denied.

Configure the Git identity used for contributions if it is not already present:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.org"
```

## Create The Workspace

Run the bootstrap from a SLURM login node. The recommended persistent workspace
location is `/data/groups/vib.ai/wouter.saelens/PERSONAL/<user>/instantomics`,
where `<user>` is your cluster username. For the usual case where `$USER` matches
that directory name, run:

```bash
curl -fsSL https://raw.githubusercontent.com/instantomics/bootstrap/main/allocate.sh | \
    bash -s -- --workspace "/data/groups/vib.ai/wouter.saelens/PERSONAL/${USER}/instantomics"
```

The command starts an interactive SLURM allocation with a 14-day default,
assembles the source-author workspace, and checks its readiness. On success it
opens an interactive shell in the workspace and keeps the allocation open.
Rerun the same command to enter the existing workspace from a later allocation;
bootstrap reuses an exact healthy checkout rather than replacing it.

The workspace must be outside `SCRATCHDIR`. The bootstrap refuses an invalid
location rather than moving or replacing existing files.

For a non-interactive bootstrap, pass the workspace explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/instantomics/bootstrap/main/bootstrap.sh | \
    bash -s -- --workspace /persistent/path
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
