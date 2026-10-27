#!/usr/bin/env bash
# Run Claude Code (Databricks Model Serving) with one Databricks managed MCP server
# on local Docker (Colima or Docker Desktop).
#
# Usage (from the repo root):
#   DATABRICKS_CONFIG_PROFILE=<u2m-profile> configs/claude-code-mcp/run_local.sh <sql|genie> [task-path] [harbor args...]
#
#   sql:   Databricks SQL MCP server  (<host>/api/2.0/mcp/sql)
#   genie: Genie One MCP server       (<host>/ai-gateway/mcp-services/system.ai.genie_one_mcp)
#
# One short-lived token is minted from the profile on this machine and used for
# Model Serving and the MCP server; no DATABRICKS_* variables reach the container.
# The MCP config is written per run under $JOBS_DIR (so the workspace URL is not
# committed) and references the token as ${DATABRICKS_MCP_TOKEN}. Which tools to
# use is appended to Claude Code's system prompt; the task is unchanged.
# Env: CLAUDE_MODEL [databricks-claude-opus-5-5], JOBS_DIR [jobs/item1-mcp], JOB_NAME [claude-<kind>-<stamp>]
set -euo pipefail

kind=${1:?usage: run_local.sh <sql|genie> [task-path] [harbor args...]}
task=${2:-tasks/databricks-mcp}
shift $(( $# >= 2 ? 2 : 1 ))
profile=${DATABRICKS_CONFIG_PROFILE:?set DATABRICKS_CONFIG_PROFILE to a Databricks CLI profile}
jobs_dir=${JOBS_DIR:-jobs/item1-mcp}
job=${JOB_NAME:-claude-$kind-$(date -u +%Y%m%dT%H%M%SZ)}

rules="You have no direct database access and no Databricks credentials. Do not call Databricks REST APIs, the Databricks CLI or a SQL driver yourself."
case $kind in
  sql)
    name=databricks-sql; path=/api/2.0/mcp/sql
    prompt="$rules Your only access to the data is the databricks-sql MCP server. Before you write the answer file you must run your query with its execute_sql_read_only tool (then poll_sql_result if the result is pending) and check the result; explore the data with it too if needed." ;;
  genie)
    name=genie-one; path=/ai-gateway/mcp-services/system.ai.genie_one_mcp
    prompt="$rules Your only access to the data is the genie-one MCP server (Genie One, a data agent). Its tools can take a few seconds to connect: wait for the genie-one server first. Before you write the answer file you must ask Genie One to run or check your query (genie_ask, then genie_poll_response until it finishes) and use what it returns." ;;
  *) echo "first argument must be sql or genie" >&2; exit 2 ;;
esac

host=$(databricks auth describe --profile "$profile" -o json | jq -er .details.host)
host=${host%/}
token=$(databricks auth token --profile "$profile" -o json | jq -er .access_token)
mkdir -p "$jobs_dir"
mcp_config="$jobs_dir/$job.mcp.json"
jq -n --arg name "$name" --arg url "$host$path" \
  '{mcpServers: {($name): {type: "http", url: $url, headers: {Authorization: "Bearer ${DATABRICKS_MCP_TOKEN}"}}}}' > "$mcp_config"

DATABRICKS_MCP_TOKEN="$token" uv run harbor run \
  -p "$task" \
  -a claude-code \
  -m "${CLAUDE_MODEL:-databricks-claude-opus-5-5}" \
  --mcp-config "$mcp_config" \
  --ak "append_system_prompt=$prompt" \
  --ak "disallowed_tools=WebSearch,WebFetch" \
  --ae "ANTHROPIC_BASE_URL=$host/serving-endpoints/anthropic" \
  --ae "ANTHROPIC_AUTH_TOKEN=$token" \
  --ae "ANTHROPIC_CUSTOM_HEADERS=x-databricks-disable-beta-headers: true" \
  --ae CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1 \
  -o "$jobs_dir" \
  --job-name "$job" \
  "$@"
