# harbor-databricks-integration

Recipes, agent adapters and tests for running [Harbor](https://github.com/harbor-framework/harbor) benchmarks with Databricks, locally (Docker/Colima) and on AWS EC2.

| # | Item | Harbor today | Docs | Status |
|---|---|---|---|---|
| 1 | Genie Code CLI as a Harbor installed agent, using models through Unity AI Gateway | Not in Harbor; no issues or PRs | [docs/01-genie-code.md](docs/01-genie-code.md) | Not started |
| 2 | Databricks Model Serving in Claude Code, Codex, Pi and OpenCode | Possible through each agent's generic custom-endpoint settings; nothing Databricks-specific | [docs/02-model-serving.md](docs/02-model-serving.md) | In progress |
| 3 | Unity AI Gateway models in the same four agents | Not in Harbor; no issues or PRs | [docs/03-unity-ai-gateway.md](docs/03-unity-ai-gateway.md) | Not started |
| 4 | Traces and results in Managed MLflow backed by Unity Catalog tables | `harbor-atif2otel` exports to open-source MLflow only | [docs/04-mlflow-uc.md](docs/04-mlflow-uc.md) | Not started |

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
docs/            one page per item: setup, local run, EC2 run, results
```

## Requirements

- [uv](https://docs.astral.sh/uv/) (all Python runs through `uv`)
- Docker (Docker Desktop or Colima) for local runs
- Databricks CLI with a configured profile
- AWS CLI with SSO for EC2 runs

```bash
uv sync
uv run harbor --version
```

The Harbor version is pinned in `pyproject.toml`. Item 1 needs the Genie Code agent from the fork branch; switch to it with the commented `[tool.uv.sources]` entry.

## Working on items in parallel

Each item has its own branch and its own full clone, for example `~/tfayyaz/harbor-databricks-integration-item-2-model-serving`. See [AGENTS.md](AGENTS.md) for the rules every session follows.
