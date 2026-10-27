# 1. Genie Code CLI with Unity AI Gateway

Status: done. The agent passes the smoke task locally and on EC2.

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

[`configs/genie-code/ec2_run.sh`](../configs/genie-code/ec2_run.sh) is item 2's throwaway-worker runner with one change: `HARBOR_SPEC` (default: the fork branch), because `genie-code` is not in a Harbor release. It launches an Amazon Linux 2023 worker (default `m7i.xlarge`, 60 GB gp3, IMDSv2, no SSH key, no inbound rules), ships the given paths through a presigned S3 URL, runs the command over SSM with only the instance role's credentials, copies `jobs/` back, and terminates the instance and deletes the bucket, also on failure or Ctrl-C. The instance, volume and bucket are tagged `Project=harbor-databricks-integration`, `Item=1`, `Owner`, `CreatedBy`.

Prerequisites, in env or a gitignored `.env.local`:
- `EC2_INSTANCE_PROFILE`: a role with `AmazonSSMManagedInstanceCore` and `secretsmanager:GetSecretValue` on the M2M secret.
- `DATABRICKS_M2M_SECRET_ID`: a Secrets Manager JSON `{host, client_id, client_secret}` for a service principal that can use Unity AI Gateway, Model Serving and the MCP servers.
- `AWS_REGION`, and a default VPC subnet with outbound internet.

[`configs/genie-code/ec2_item1.sh`](../configs/genie-code/ec2_item1.sh) is the worker command. It reads the secret with the instance role and runs `genie-code` on `tasks/smoke` with OAuth M2M (the agent mints a token per trial), then Claude Code with each MCP server on `tasks/databricks-mcp` with one token minted on the worker.

```bash
aws sts get-caller-identity               # check the account; aws sso login if expired
set -a; . ./.env.local; set +a
JOBS_DIR=$PWD/jobs/item1-ec2 WORKER_ENV="DATABRICKS_M2M_SECRET_ID=$DATABRICKS_M2M_SECRET_ID" \
  configs/genie-code/ec2_run.sh configs/genie-code/ec2_item1.sh configs tasks pyproject.toml
```

Results land in `$JOBS_DIR/ec2-<stamp>/jobs/`.

## Results

Smoke task [`tasks/smoke`](../tasks/smoke) (write `/app/answer.txt` = `ok\n`), one trial per model. Locally: macOS + Colima, U2M token, Genie Code CLI 0.2.0, 2026-10-22. EC2: `m7i.xlarge` Amazon Linux 2023, OAuth M2M from Secrets Manager, Genie Code CLI 0.2.1 (the latest release when the worker installed it), 2026-10-27.

| Agent | Model | Local | EC2 | Agent setup (local / EC2) | Agent run (local / EC2) | Tokens in / out (EC2) |
|---|---|---|---|---|---|---|
| `genie-code` | `databricks/gpt-5.4-mini` | Pass (1/1) | Pass (1/1) | 23 s / 50 s | 7 s / 6 s | 31,674 / 112 |
| `genie-code` | `databricks/gpt-5.6-sol` | Pass (1/1) | Pass (1/1) | 21 s / 49 s | 7 s / 6 s | 27,137 / 82 |

Each pass was checked in the trajectory for a real tool call (`apply_patch` or `exec`) and a final model turn. The EC2 worker was terminated and its bucket deleted; no token was found in the copied-back `jobs/`.

## Gotchas

- **Unknown model names fall back silently.** Genie only runs models in its built-in catalog; any other `-m` value runs Genie's default. The agent detects this from the rollout and fails the trial.
- **The model is set in `config.toml`**, which the agent writes; Genie's onboarding is skipped.
- **No sandbox inside containers.** Genie's bwrap sandbox needs privileges an unprivileged container does not have, so the agent runs with `--dangerously-bypass-approvals-and-sandbox`.
- **Pin the version for repeatable runs.** Without `--ak version=...` the agent installs the latest release (0.2.0 locally, 0.2.1 a few days later on EC2).
- **One token per trial.** The token is minted when the trial starts and lasts about an hour.
