# 2. Databricks Model Serving in Claude Code, Codex, Pi and OpenCode

Status: done. All four agents pass the smoke task locally and on EC2 (2026-10-22, Harbor 0.24.0).

Harbor 0.24.0 has no Databricks-specific code in these four agents. Each one reaches the `databricks-*` foundation-model endpoints under `https://<workspace>.cloud.databricks.com/serving-endpoints` through its generic custom-endpoint settings. This page shows the config for each agent, the commands for local (Docker/Colima) and AWS EC2 runs, and the results of the runs we did.

## How it works

| Agent | Harbor class | API it sends | Base URL | Token env |
|---|---|---|---|---|
| Claude Code | `databricks_agents:DatabricksClaudeCode` | Anthropic Messages | `<host>/serving-endpoints/anthropic` | `ANTHROPIC_AUTH_TOKEN` |
| Codex | `databricks_agents:DatabricksCodex` | OpenAI Responses | `<host>/serving-endpoints` (named provider) | `OPENAI_API_KEY` |
| Pi | `databricks_agents:DatabricksPi` | OpenAI Responses (`model_api: openai-responses`) | `<host>/serving-endpoints` | `OPENAI_API_KEY` |
| OpenCode | `databricks_agents:DatabricksOpenCode` | OpenAI Responses (`@ai-sdk/openai`) | `<host>/serving-endpoints` | `OPENAI_API_KEY` |

- **Per-trial tokens.** [`agents/databricks_agents.py`](../agents/databricks_agents.py) subclasses the four stock agents. Before each trial it runs [`scripts/databricks_token.sh`](../scripts/databricks_token.sh) on the Harbor host and puts the token into the agent env, then refreshes it after 30 minutes. Jobs can therefore outlive the ~1 h token, and an M2M client secret never enters a task container. In the YAML the token key holds the placeholder `minted-per-trial`.
- **Token sources** (first match wins): `DATABRICKS_M2M_SECRET_ID` (AWS Secrets Manager JSON `{host, client_id, client_secret}`, read with the EC2 instance role), `DATABRICKS_CLIENT_ID` + `DATABRICKS_CLIENT_SECRET` (OAuth M2M), or `DATABRICKS_PROFILE` (a CLI U2M profile, for local runs).
- **Host rendering.** Harbor expands `${VAR}` only when it is the whole value, so `${DATABRICKS_HOST}/serving-endpoints` would reach the agent literally. The configs use `__DATABRICKS_HOST__`, which [`scripts/run_local.sh`](../scripts/run_local.sh) replaces before calling `harbor run`.
- **Versions.** Each config pins the agent version that passed below. Bump it deliberately and rerun the smoke.

### Configs

All four are in [`configs/model-serving/`](../configs/model-serving/).

Claude Code ([`claude-code.yaml`](../configs/model-serving/claude-code.yaml)):

```yaml
- import_path: databricks_agents:DatabricksClaudeCode
  model_name: databricks-claude-haiku-5-5
  kwargs:
    version: "2.1.308"
    disallowed_tools: WebSearch,WebFetch
  env:
    ANTHROPIC_AUTH_TOKEN: minted-per-trial
    ANTHROPIC_BASE_URL: __DATABRICKS_HOST__/serving-endpoints/anthropic
    ANTHROPIC_CUSTOM_HEADERS: "x-databricks-disable-beta-headers: true"
    CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS: "1"
```

Codex ([`codex.yaml`](../configs/model-serving/codex.yaml)): a named `databricks` provider with `supports_websockets: false`, set through the native `config` kwarg.

```yaml
- import_path: databricks_agents:DatabricksCodex
  model_name: databricks-gpt-6-sol
  kwargs:
    version: "0.163.0"
    reasoning_effort: low
    config:
      model_provider: databricks
      model_providers:
        databricks:
          name: Databricks
          base_url: __DATABRICKS_HOST__/serving-endpoints
          env_key: OPENAI_API_KEY
          wire_api: responses
          supports_websockets: false
          request_max_retries: 2
          stream_max_retries: 2
  env:
    OPENAI_API_KEY: minted-per-trial
```

Pi ([`pi.yaml`](../configs/model-serving/pi.yaml)): Harbor 0.24.0 writes Pi's `models.json` itself (provider `harbor-endpoint`) when `OPENAI_BASE_URL` and `model_api` are set. The bind-mounted `models.json` and the `!printenv` workaround needed on Harbor 0.20 are no longer required.

```yaml
- import_path: databricks_agents:DatabricksPi
  model_name: openai/databricks-gpt-6-sol
  kwargs:
    version: "1.2.0"
    model_api: openai-responses
  env:
    OPENAI_API_KEY: minted-per-trial
    OPENAI_BASE_URL: __DATABRICKS_HOST__/serving-endpoints
```

OpenCode ([`opencode.yaml`](../configs/model-serving/opencode.yaml)): for `openai/<endpoint>`, Harbor writes `provider.openai.options.baseURL` from `OPENAI_BASE_URL`. OpenCode's built-in `openai` provider calls the Responses API.

```yaml
- import_path: databricks_agents:DatabricksOpenCode
  model_name: openai/databricks-gpt-6-sol
  kwargs:
    version: "0.0.0-beta-202605152242"
  env:
    OPENAI_API_KEY: minted-per-trial
    OPENAI_BASE_URL: __DATABRICKS_HOST__/serving-endpoints
```

## Setup

```bash
uv sync                                   # installs harbor==0.24.0 from pyproject.toml
databricks auth profiles                  # pick a profile; always pass --profile
export DATABRICKS_PROFILE=<u2m-profile>
export DATABRICKS_HOST=$(databricks auth describe --profile "$DATABRICKS_PROFILE" -o json | jq -r '.details.host // .host')
databricks serving-endpoints list --profile "$DATABRICKS_PROFILE" -o json | jq -r '.[].name' | grep '^databricks-'
```

Network-specific settings that must not be committed (for example a private npm mirror) go in a gitignored `.env.local` at the repo root. `run_local.sh`, `ec2_run.sh` and `ec2_smoke.sh` load it:

```bash
# .env.local (gitignored)
NPM_CONFIG_REGISTRY=https://<your-npm-mirror>/
AWS_REGION=<region>
EC2_INSTANCE_PROFILE=<instance-profile-name>
DATABRICKS_M2M_SECRET_ID=<secrets-manager-id>
```

Check that each endpoint answers on the API its agent uses, including a tool call for the OpenAI one, before starting Harbor:

```bash
scripts/preflight.sh databricks-claude-haiku-5-5   # Anthropic Messages
scripts/preflight.sh databricks-gpt-6-sol          # OpenAI Responses + function tool
# model=databricks-gpt-6-sol http=200 seconds=1.49 url=/serving-endpoints/responses
```

## Run locally

Docker runs in Colima on macOS; see [colima.md](colima.md). Use a unique jobs dir per session.

```bash
export JOBS_DIR=$PWD/jobs/item2-local
scripts/run_smoke.sh claude-code           # one agent
scripts/run_smoke.sh all                   # claude-code codex pi opencode, one after another
# agent=claude-code job=item2-claude-code-<stamp> reward=1.0
```

Any job config runs the same way; extra arguments go to `harbor run`:

```bash
scripts/run_local.sh configs/model-serving/codex.yaml --path tasks/smoke --job-name my-codex-run
```

Check the agent log for a real model turn, not just reward 1. For example, for Claude Code:

```bash
jq -c 'select(.type=="result") | {subtype,is_error,num_turns}' jobs/item2-local/<job>/*/agent/claude-code.txt
```

## Run on EC2

[`scripts/ec2_run.sh`](../scripts/ec2_run.sh) launches a throwaway Amazon Linux 2023 worker (default `m7i.xlarge`, 60 GB gp3, IMDSv2, no SSH key, no inbound rules). It ships the repo paths through a presigned S3 URL, runs the command over SSM with only the instance role's credentials, copies `jobs/` back, and then terminates the instance and deletes the bucket, including on failure or Ctrl-C. The instance, its volume and the bucket are tagged `Project=harbor-databricks-integration`, `Item=2`, `Owner`, `CreatedBy`.

Prerequisites, all supplied through env or `.env.local`:
- `EC2_INSTANCE_PROFILE`: a role with `AmazonSSMManagedInstanceCore` and `secretsmanager:GetSecretValue` on the M2M secret.
- `DATABRICKS_M2M_SECRET_ID`: a Secrets Manager JSON `{host, client_id, client_secret}` for a service principal that can query the endpoints.
- A default VPC subnet with outbound internet.

```bash
aws sts get-caller-identity               # check the account; aws sso login if expired
export DATABRICKS_HOST=$(databricks auth describe --profile <m2m-profile> -o json | jq -r '.details.host // .host')
JOBS_DIR=$PWD/jobs/item2-ec2 scripts/ec2_smoke.sh            # all four agents
JOBS_DIR=$PWD/jobs/item2-ec2 scripts/ec2_smoke.sh codex pi   # a subset
```

The worker installs Docker with the compose and buildx plugins, `uv`, and the Harbor version from `pyproject.toml`. It uses public npm: a laptop's npm mirror is not passed through. Results land in `$JOBS_DIR/ec2-<stamp>/jobs/`.

## Results

Smoke task: [`tasks/smoke`](../tasks/smoke) (write `/app/answer.txt` = `ok\n`), 1 attempt per agent, run one agent at a time. Harbor 0.24.0, run on 2026-10-22. Locally: macOS + Colima, U2M token. EC2: `m7i.xlarge` AL2023, OAuth M2M token from Secrets Manager. Every pass was checked in the agent log for real tool calls, a final model turn, and no 401/403.

| Agent | Version | Model | Local | EC2 | Notes |
|---|---|---|---|---|---|
| Claude Code | 2.1.308 | `databricks-claude-haiku-5-5` | Pass (2/5) | Pass (2/2) | Tools: Bash. The 3 local failures were infrastructure, all before the fixes: the Colima disk I/O error, then two `AgentSetupTimeoutError`s (the CDN binary download was cut off with `curl: (18)`; fixed by the npm-mirror install and the 3x setup timeout). |
| Codex | 0.163.0 | `databricks-gpt-6-sol` | Pass (3/3) | Pass (1/2) | First EC2 run failed with `AgentSetupTimeoutError`: 18 min in `apt-get install nodejs npm ripgrep`. Passed after skipping the unused apt Node. No WebSocket reconnects. |
| Pi | 1.2.0 | `databricks-gpt-6-sol` | Pass (2/2) | Pass (2/2) | Tools: write. `api: openai-responses` via Harbor's `harbor-endpoint` provider. |
| OpenCode | 0.0.0-beta-202605152242 | `databricks-gpt-6-sol` | Pass (3/3) | Pass (2/2) | Tools: read, apply_patch. npm's `latest` tag for `opencode-ai` is this beta build. |

Final runs with the committed configs:

| Run | Claude Code | Codex | Pi | OpenCode |
|---|---|---|---|---|
| Local, pinned versions (`run_smoke.sh all`) | 1.0 (setup 428 s, run 6 s) | 1.0 (576 s, 8 s) | 1.0 (311 s, 8 s) | 1.0 (640 s, 17 s) |
| Local, after skipping apt Node | (unchanged path) | 1.0 (64 s, 9 s) | (unchanged) | 1.0 (75 s, 7 s) |
| EC2 run 1 | 1.0 (714 s, 5 s) | **fail**: `AgentSetupTimeoutError` (1080 s) | 1.0 (37 s, 4 s) | 1.0 (516 s, 11 s) |
| EC2 run 2, after skipping apt Node | 1.0 (24 s, 4 s) | 1.0 (22 s, 7 s) | 1.0 (66 s, 4 s) | 1.0 (30 s, 10 s) |

Both EC2 workers were terminated and their buckets deleted. Afterwards no instances, volumes or buckets tagged `Item=2` remained.

Not run: the optional data-eng-bench check (step 5).

## Gotchas confirmed on Harbor 0.24.0

- **gpt-6-sol and tools.** `databricks-gpt-6-sol` returns `400 "Function tools with reasoning_effort are not supported ... in /v1/chat/completions"` unless `reasoning_effort` is `none`. Coding agents need tools, so all three OpenAI-side agents use the Responses API. `databricks-gpt-5-3-codex` serves Responses only (`400 "only supports the Responses API"` on `/chat/completions`), so use it only with Codex or Pi on `openai-responses`.
- **Claude Code** still needs `ANTHROPIC_CUSTOM_HEADERS="x-databricks-disable-beta-headers: true"` and `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`.
- **Codex** still needs the named provider with `supports_websockets: false`. With it, the logs had no reconnects.
- **Pi** no longer needs a bind-mounted `models.json` or `!printenv`. Harbor 0.24.0 writes `models.json` with `apiKey: "$OPENAI_API_KEY"` from `OPENAI_BASE_URL` plus the `model_api` kwarg, and Pi 1.2.0 resolves it.
- **`${VAR}` is still expanded only as the whole value.** Keep `__DATABRICKS_HOST__` and render it (`run_local.sh`).
- **The NodeSource Node conflict is gone.** Harbor 0.24.0 checks each system dependency separately (`command -v node`, `command -v npm`), so an image that already has Node no longer gets Debian's `npm` on top. The 0.23 `_KeepImageNode` workaround was dropped. Not exercised here: the smoke image has no Node.
- **Unused apt Node is the real cost.** On glibc images Harbor 0.24.0 still runs `apt-get install nodejs npm` for Claude Code, Codex and OpenCode, although Codex and OpenCode then install Node 22 with nvm and Claude Code downloads a native binary. On Ubuntu 24.04 that took 9–18 min on EC2 and pushed Codex past the setup timeout. `_SkipUnusedAptNode` in `agents/databricks_agents.py` drops those two packages, except on musl images and for Claude Code's npm-mirror install. Setup went to 22–66 s on EC2.
- **Setup timeout.** Configs set `agent_setup_timeout_multiplier: 3` (360 s → 1080 s) for slow networks.
- **npm.** Where public npm is intercepted (`curl` TLS errors from containers), set `NPM_CONFIG_REGISTRY` in `.env.local`. The agent subclasses copy it into the agent env. EC2 workers use public npm.
- **Token refresh** starts from `None`, not 0: a fresh EC2 worker's monotonic clock is near zero.
- **EBS.** Keep `VOLUME_GB` at 150 or below; 200 GB volumes were rejected by the account policy in earlier work. The default here is 60.
- **Concurrency.** These runs used 1 trial at a time. Stay at 8 or fewer concurrent trials per endpoint.
- **Colima disk.** A full Mac disk corrupted the Colima VM mid-session; see [colima.md](colima.md).
