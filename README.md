# harbor-databricks-integration

Recipes, agent adapters and tests for running [Harbor](https://github.com/harbor-framework/harbor) benchmarks with Databricks, locally (Docker/Colima) and on AWS EC2.

| # | Item | Harbor today | Docs | Status |
|---|---|---|---|---|
| 1 | Genie Code CLI as a Harbor installed agent, using models through Unity AI Gateway | Not in Harbor; no issues or PRs | [docs/01-genie-code.md](docs/01-genie-code.md) | Not started |
| 2 | Databricks Model Serving in Claude Code, Codex, Pi and OpenCode | Possible through each agent's generic custom-endpoint settings; nothing Databricks-specific | [docs/02-model-serving.md](docs/02-model-serving.md) | Done: all four agents pass the smoke task locally and on EC2 (Harbor 0.24.0) |
| 3 | Unity AI Gateway models in the same four agents | Not in Harbor; no issues or PRs | [docs/03-unity-ai-gateway.md](docs/03-unity-ai-gateway.md) | Not started |
| 4 | Traces and results in Managed MLflow backed by Unity Catalog tables | `harbor-atif2otel` exports to open-source MLflow only | [docs/04-mlflow-uc.md](docs/04-mlflow-uc.md) | Not started |
| 5 | Terminal-Bench 4 (`terminal-bench/terminal-bench`, 66 tasks; CPU-only subset of 63) with the item 2 agents | Published on the Harbor Hub | [docs/05-terminal-bench-4.md](docs/05-terminal-bench-4.md) | Not started |
| 6 | data-eng-bench (`snowflake-labs/data-eng-bench`, 103 dbt tasks) on its public DuckDB backend with the item 2 agents | Published on the Harbor Hub | [docs/06-data-eng-bench.md](docs/06-data-eng-bench.md) | Not started |

Each item is tested locally and on EC2, and the docs record the results.

## Layout

```
agents/          Harbor agent subclasses (per-trial token minting, gateway config)
configs/         Harbor job YAMLs, one directory per item
  genie-code/    item 1
  model-serving/ item 2
  gateway/       item 3
mlflow/          item 4: MLflow/Unity Catalog uploader and results writer
scripts/         run_local.sh, ec2_run.sh, token minting
tasks/smoke/     tiny task that proves an agent can reach its model and write a file
benchmarks/      benchmark-specific fetch scripts and job configs (items 5 and 6)
docs/            one page per item: setup, local run, EC2 run, results
```

## Requirements

- [uv](https://docs.astral.sh/uv/) (all Python runs through `uv`)
- Docker for local runs. On macOS the runs here use [Colima](https://github.com/abiosoft/colima) (see below).
- Databricks CLI with a configured profile
- AWS CLI with SSO for EC2 runs

```bash
uv sync
uv run harbor --version
```

The Harbor version is pinned in `pyproject.toml`. Item 1 needs the Genie Code agent from the fork branch; switch to it with the commented `[tool.uv.sources]` entry.

### Why Colima for local runs

Harbor drives a Docker daemon through the standard `docker` and `docker compose` CLIs, so any Docker engine works. On macOS we use Colima because it is:
- **Free and open source (MIT).** There's no Docker Desktop licence or sign-in, which matters for unattended and team use.
- **Scriptable and sized to the workload.** It's CLI-only, and the Linux VM's CPU, memory and disk are set at start, for example `colima start --cpu 8 --memory 16 --disk 150`. Parallel trials need that headroom.
- **Normal Docker storage.** Its VM uses overlay storage on ext4, so copy-on-write layers behave as on a Linux host, with no VFS-style write amplification. We checked this while measuring disk use per trial.
- **Disposable.** `colima delete` resets the VM, images and build cache in one step.

Gotchas:
- Colima mounts only your home directory into the VM. Keep task and jobs directories under `$HOME`, not `/tmp`, or the verifier can't write its reward file.
- `docker compose down` doesn't clear BuildKit's cache. Reclaim it with `docker builder prune -af` when disk runs low.

### Local-only settings

Package mirrors, proxies and other machine-specific settings go in `.env.local`, which is gitignored. Copy `.env.example` and fill it in; the scripts load it if it exists. Never put those values in committed files.

## Working on items in parallel

Each item has its own branch and its own full clone, for example `~/tfayyaz/harbor-databricks-integration-item-2-model-serving`. See [AGENTS.md](AGENTS.md) for the rules every session follows.
