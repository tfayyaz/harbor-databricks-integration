#!/usr/bin/env bash
# Item 1 checks on an EC2 worker (run by configs/genie-code/ec2_run.sh):
#   genie-code on tasks/smoke with OAuth M2M (the agent mints a token per trial),
#   then Claude Code with the Databricks SQL and the Genie One MCP servers on
#   tasks/databricks-mcp, with one short-lived token minted here.
# The M2M credentials come from AWS Secrets Manager with the instance role:
#   DATABRICKS_M2M_SECRET_ID  JSON {host, client_id, client_secret}
# Env: GENIE_CODE_MODELS [databricks/gpt-5.4-mini databricks/gpt-5.6-sol]
set -euo pipefail

secret=$(aws secretsmanager get-secret-value --secret-id "${DATABRICKS_M2M_SECRET_ID:?}" \
  --query SecretString --output text)
host=$(jq -er .host <<<"$secret"); host=${host%/}
client_id=$(jq -er .client_id <<<"$secret")
client_secret=$(jq -er .client_secret <<<"$secret")
unset secret
dir=$(dirname "$0")

for model in ${GENIE_CODE_MODELS:-databricks/gpt-5.4-mini databricks/gpt-5.6-sol}; do
  DATABRICKS_HOST="$host" DATABRICKS_CLIENT_ID="$client_id" DATABRICKS_CLIENT_SECRET="$client_secret" \
    JOB_NAME="ec2-genie-code-${model##*/}" "$dir/run_local.sh" "$model" tasks/smoke || echo "genie-code $model: harbor failed"
done

token=$(curl -fsS -u "$client_id:$client_secret" "$host/oidc/v1/token" \
  -d grant_type=client_credentials -d scope=all-apis | jq -er .access_token)
for kind in sql genie; do
  DATABRICKS_HOST="$host" DATABRICKS_TOKEN="$token" JOB_NAME="ec2-claude-$kind" \
    "$dir/../claude-code-mcp/run_local.sh" "$kind" tasks/databricks-mcp || echo "claude-code $kind: harbor failed"
done
