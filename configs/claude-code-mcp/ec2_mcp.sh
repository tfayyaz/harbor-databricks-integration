#!/usr/bin/env bash
# Item 1 check on an EC2 worker (run by configs/claude-code-mcp/ec2_run.sh):
#   Claude Code with the Databricks SQL and the Genie One MCP servers on
#   tasks/databricks-mcp, with one short-lived token minted here.
# The M2M credentials come from AWS Secrets Manager with the instance role:
#   DATABRICKS_M2M_SECRET_ID  JSON {host, client_id, client_secret}
set -euo pipefail

secret=$(aws secretsmanager get-secret-value --secret-id "${DATABRICKS_M2M_SECRET_ID:?}" \
  --query SecretString --output text)
host=$(jq -er .host <<<"$secret"); host=${host%/}
client_id=$(jq -er .client_id <<<"$secret")
client_secret=$(jq -er .client_secret <<<"$secret")
unset secret
dir=$(dirname "$0")

token=$(curl -fsS -u "$client_id:$client_secret" "$host/oidc/v1/token" \
  -d grant_type=client_credentials -d scope=all-apis | jq -er .access_token)
for kind in sql genie; do
  DATABRICKS_HOST="$host" DATABRICKS_TOKEN="$token" JOB_NAME="ec2-claude-$kind" \
    "$dir/run_local.sh" "$kind" tasks/databricks-mcp || echo "claude-code $kind: harbor failed"
done
