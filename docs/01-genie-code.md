# 1. Genie Code CLI with Unity AI Gateway

Status: agent written and tested locally; EC2 run not done yet.

[Genie Code](https://github.com/databricks/genie-code-cli) (the `genie` command) is Databricks' terminal coding agent. It is built on the Codex CLI and gets its models from Unity AI Gateway. Harbor has no Genie Code agent, so this item adds one: `genie-code`, on the [`add-genie-code-agent`](https://github.com/tfayyaz/harbor/tree/add-genie-code-agent) branch of the Harbor fork (`src/harbor/agents/installed/genie_code.py`, 26 unit tests in `tests/unit/agents/installed/test_genie_code.py`).

For Claude Code with the Databricks SQL and Genie One MCP servers, see [01-claude-code-databricks-mcp.md](01-claude-code-databricks-mcp.md).

## How the agent works

`GenieCode` subclasses Harbor's `Codex` agent and reuses its trajectory conversion (Genie writes Codex-format rollouts). It replaces what is specific to OpenAI:

| | What the agent does |
|---|---|
| Install | runs Genie Code's release installer in the container (a self-contained package with `genie` and `rg`) and the Databricks CLI installer, for Genie's workspace tools; skipped if the requested version is already installed |
| Config | writes `$GENIE_HOME/config.toml` itself, so Genie's interactive onboarding and a `.databrickscfg` are not needed. The model provider is `databricks` with `base_url = $DATABRICKS_HOST/ai-gateway/codex/v1` |
| Auth | the token is resolved on the Harbor host for each trial, from `DATABRICKS_TOKEN`, OAuth M2M (`DATABRICKS_CLIENT_ID` + `DATABRICKS_CLIENT_SECRET`, exchanged at `/oidc/v1/token`; the secret never enters the container) or a CLI profile (`DATABRICKS_CONFIG_PROFILE`). Only the token goes into the container, and only for the `genie exec` command; the provider gets it from an auth command that prints `$DATABRICKS_TOKEN` |
| Run | `genie exec --json --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox`. Genie's own bwrap sandbox cannot start in an unprivileged container, so the container is the sandbox, as for Codex |
| Model | `-m databricks/<model>`, or omit `-m` for Genie's default. Genie silently falls back to its default model for names outside its catalog, so the agent reads the model from the rollout and fails the trial if it differs |
| Options | `--ak reasoning_effort=<none…ultra>`, `--ak version=<x.y.z>`, and native `config.toml` settings, as for Codex |

`DATABRICKS_HOST` is required. OAuth tokens last about an hour, which bounds a single trial.

## Setup

You need a Databricks workspace with Unity AI Gateway enabled and a Databricks CLI profile for it.

`main` pins the released Harbor, which has no `genie-code` agent. Point `[tool.uv.sources]` in `pyproject.toml` at the fork, either a local clone or the branch on GitHub:

```toml
[tool.uv.sources]
harbor = { path = "../harbor-add-genie-code-agent", editable = true }
# or: harbor = { git = "https://github.com/tfayyaz/harbor", branch = "add-genie-code-agent" }
```

```bash
git clone -b add-genie-code-agent https://github.com/tfayyaz/harbor ../harbor-add-genie-code-agent   # for the path source
uv sync

databricks auth profiles                 # pick a profile; always pass --profile
export DATABRICKS_CONFIG_PROFILE=<profile>
```

## Run locally

[`configs/genie-code/run_local.sh`](../configs/genie-code/run_local.sh) reads the workspace host from the profile and runs Harbor; the agent mints a short-lived token from the profile for each trial.

```bash
configs/genie-code/run_local.sh                                    # tasks/smoke, databricks/gpt-5.4-mini
configs/genie-code/run_local.sh databricks/gpt-5.6-sol             # another model
configs/genie-code/run_local.sh databricks/gpt-5.6-sol <task-dir>  # any Harbor task
```

The same with `harbor run` directly:

```bash
DATABRICKS_HOST=$(databricks auth describe --profile "$DATABRICKS_CONFIG_PROFILE" -o json | jq -r .details.host) \
  uv run harbor run -p tasks/smoke -a genie-code -m databricks/gpt-5.6-sol -o jobs/item1-local
```

Check the agent log for a real model turn, not just reward 1: `jobs/item1-local/<job>/*/agent/genie-code.txt` is Genie's JSON event stream and `agent/trajectory.json` the ATIF trajectory with token counts.

Local runs use [Colima](https://github.com/abiosoft/colima) as the Docker runtime on macOS. Colima is free and open source, runs from the command line with no desktop app or licence, and lets you set the VM's CPU, memory and disk explicitly (`colima start --cpu 8 --memory 16 --disk 100`), which matters because Harbor starts one container per trial. On Apple Silicon it runs arm64 images natively. Docker Desktop also works; Harbor only needs a working `docker` and `docker compose`.

If `docker run` fails with `input/output error` under `/var/lib/containerd`, the Colima VM's disk is damaged. `colima restart` fixes it, but it stops every running container, so check `docker ps` first on a shared machine.

## Run on EC2

Not done yet for this item.

## Results

Smoke task [`tasks/smoke`](../tasks/smoke) (write `/app/answer.txt` = `ok\n`), one trial per model, Genie Code CLI 0.2.0, run locally on macOS + Colima with a U2M token on 2026-10-22.

| Agent | Model | Local | EC2 | Agent setup | Agent run | Tokens in / out |
|---|---|---|---|---|---|---|
| `genie-code` | `databricks/gpt-5.4-mini` | Pass (1/1) | not run | 23 s | 7 s | 31,662 / 126 |
| `genie-code` | `databricks/gpt-5.6-sol` | Pass (1/1) | not run | 21 s | 7 s | 27,132 / 77 |

## Gotchas

- **Unknown model names fall back silently.** Genie only runs models in its built-in catalog; any other `-m` value runs Genie's default. The agent detects this from the rollout and fails the trial.
- **The model is set in `config.toml`**, which the agent writes; Genie's onboarding is skipped.
- **No sandbox inside containers.** Genie's bwrap sandbox needs privileges an unprivileged container does not have, so the agent runs with `--dangerously-bypass-approvals-and-sandbox`.
- **One token per trial.** The token is minted when the trial starts and lasts about an hour.
