# Claude Code with the Databricks SQL and Genie One MCP servers

Status: tested locally; EC2 run not done yet.

Claude Code can reach Databricks data through a Databricks managed MCP server instead of calling Databricks itself. Two servers are covered:

| Server | URL | Tools |
|---|---|---|
| Databricks SQL | `https://<workspace>.cloud.databricks.com/api/2.0/mcp/sql` | `execute_sql`, `execute_sql_read_only`, `poll_sql_result` |
| Genie One (through Unity AI Gateway) | `https://<workspace>.cloud.databricks.com/ai-gateway/mcp-services/system.ai.genie_one_mcp` | `genie_ask`, `genie_poll_response`, `genie_get_query_result`, `genie_cancel_response` |

With the SQL server Claude Code writes and runs the SQL. With Genie One, Claude Code asks a second agent (Genie One finds the tables, writes and runs the SQL in Databricks) and uses its answer.

This needs no Harbor changes. Harbor's `claude-code` agent already has what is needed:

- `--mcp-config <file>` adds MCP servers for a run (a Claude-style `.mcp.json`). Header values written as `${VAR}` are filled in from the host environment and passed to Claude Code without being written to its config files.
- `--ak append_system_prompt=<text>` appends text to Claude Code's system prompt, so the task's `instruction.md` stays unchanged.
- Model Serving works as in [item 2](02-model-serving.md): `ANTHROPIC_BASE_URL=<host>/serving-endpoints/anthropic` and a Databricks token as `ANTHROPIC_AUTH_TOKEN`.

## Setup

You need a workspace with Unity AI Gateway (for Genie One), a SQL warehouse the identity can use, a Claude endpoint in Model Serving (`databricks-claude-opus-5-5` here), and a Databricks CLI profile.

```bash
uv sync
databricks auth profiles                  # pick a profile; always pass --profile
export DATABRICKS_CONFIG_PROFILE=<profile>
```

## Run locally

[`configs/claude-code-mcp/run_local.sh`](../configs/claude-code-mcp/run_local.sh) runs one task with one MCP server. It mints one short-lived token from the profile on the host and uses it for Model Serving and the MCP server.

```bash
configs/claude-code-mcp/run_local.sh sql                 # tasks/databricks-mcp with the Databricks SQL MCP
configs/claude-code-mcp/run_local.sh genie               # the same task with Genie One MCP
configs/claude-code-mcp/run_local.sh genie <task-dir>    # any task that uses Databricks data
```

What the script does, step by step:

```bash
HOST=$(databricks auth describe --profile "$DATABRICKS_CONFIG_PROFILE" -o json | jq -r .details.host)
TOKEN=$(databricks auth token --profile "$DATABRICKS_CONFIG_PROFILE" -o json | jq -r .access_token)

# 1. The MCP config, written per run (keep it out of git: it holds the workspace URL).
cat > jobs/genie-one.mcp.json <<EOF
{"mcpServers": {"genie-one": {"type": "http",
  "url": "$HOST/ai-gateway/mcp-services/system.ai.genie_one_mcp",
  "headers": {"Authorization": "Bearer \${DATABRICKS_MCP_TOKEN}"}}}}
EOF

# 2. Harbor run: model on Model Serving, the MCP server, and what to use in the system prompt.
DATABRICKS_MCP_TOKEN="$TOKEN" uv run harbor run -p tasks/databricks-mcp -a claude-code \
  -m databricks-claude-opus-5-5 \
  --mcp-config jobs/genie-one.mcp.json \
  --ak "append_system_prompt=You have no direct database access and no Databricks credentials. ... Before you write the answer file you must ask Genie One to run or check your query (genie_ask, then genie_poll_response until it finishes) and use what it returns." \
  --ak "disallowed_tools=WebSearch,WebFetch" \
  --ae "ANTHROPIC_BASE_URL=$HOST/serving-endpoints/anthropic" --ae "ANTHROPIC_AUTH_TOKEN=$TOKEN" \
  --ae "ANTHROPIC_CUSTOM_HEADERS=x-databricks-disable-beta-headers: true" \
  --ae CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1 \
  -o jobs/item1-mcp
```

The full system-prompt texts for both servers are in the script.

Check that the server was used, not just the reward: `agent/claude-code.txt` starts with an `init` event listing `mcp_servers` and their status (`connected` or `pending`), and `agent/trajectory.json` lists the tool calls (`mcp__genie-one__genie_ask`, `mcp__databricks-sql__execute_sql_read_only`, …).

```bash
jq -r '.steps[] | select(.tool_calls) | .tool_calls[].function_name' jobs/item1-mcp/<job>/*/agent/trajectory.json
```

## Task

[`tasks/databricks-mcp`](../tasks/databricks-mcp) asks a question about `samples.tpch`, the sample data every Databricks workspace has: how many orders with status `'F'` were placed in 1995 by `BUILDING` customers. It needs a join and a filter, and the answer (47911) is the same in every workspace, so the verifier only compares `/app/answer.txt` with it and needs no Databricks access.

## Run on EC2

Not done yet.

## Results

`tasks/databricks-mcp`, one trial each, Claude Code 2.1.311 with `databricks-claude-opus-5-5`, run locally on macOS + Colima with a U2M token on 2026-10-27.

| MCP server | Reward | Tool calls | Agent run | Tokens in / out |
|---|---|---|---|---|
| Databricks SQL | 1.0 | `execute_sql_read_only`, then Bash to write the answer | 16 s | 83,297 / 350 |
| Genie One | 1.0 | `genie_ask`, `genie_poll_response` ×2, then Bash to write the answer | 27 s | 151,090 / 741 |

Agent setup (installing Claude Code in the container) took 4–5 minutes on this network. In both runs the container got only `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_CUSTOM_HEADERS` and `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` as agent environment, and the MCP server's status was `connected`.

The same setup also passed one migrated BIRD text-to-SQL task (`superhero__786`) with each server.

## Gotchas

- **Say that the server must be used.** With a system prompt that only said which tools to use for checking, Claude Code wrote the SQL from the schema in the instruction and never called the server (it still passed). With "before you write the answer file you must run/check your query with …", it used the server every time.
- **Genie One's server can connect late.** Claude Code starts while HTTP MCP servers are still connecting. In one run the Genie One server was `pending` at start, so its tools were not offered; the prompt now tells Claude Code to wait for it (Claude Code has a `WaitForMcpServers` tool for this).
- **Instructions, not isolation.** The model token is a full workspace token, so the container could call Databricks APIs directly with it. The system prompt forbids it, and the trajectory shows every tool call, so a bypass would be visible, but nothing blocks it. Keeping Claude Code off Databricks entirely needs a model credential with no data access, for example a separate model-serving workspace.
- **Genie One keeps history.** Its Memory is on and MCP cannot delete conversations, so every trial leaves a conversation in the identity's Genie One history.
- **Keep the MCP config out of git.** It holds the workspace URL; `jobs/` is gitignored.
