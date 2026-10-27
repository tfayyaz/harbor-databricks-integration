#!/usr/bin/env bash
# Print a short-lived Databricks access token for Model Serving.
# Token sources, first match wins:
#   DATABRICKS_PROFILE         Databricks CLI U2M profile (local runs)
#   DATABRICKS_CLIENT_ID + DATABRICKS_CLIENT_SECRET + DATABRICKS_HOST   OAuth M2M
#   DATABRICKS_M2M_SECRET_ID   AWS Secrets Manager JSON {host, client_id, client_secret},
#                              read with the EC2 instance role (needs AWS_REGION)
# An explicit U2M profile wins, so a .env.local that also holds the EC2 secret id
# doesn't switch local runs to M2M. EC2 workers only get DATABRICKS_M2M_SECRET_ID.
set -euo pipefail

mint() { # host client_id client_secret
  curl -fsS -u "$2:$3" "${1%/}/oidc/v1/token" \
    -d 'grant_type=client_credentials&scope=all-apis' | jq -er .access_token
}

if [[ -n "${DATABRICKS_PROFILE:-}" ]]; then
  # `databricks auth token` rejects M2M profiles; use the M2M variables below for those.
  databricks auth token --profile "$DATABRICKS_PROFILE" -o json | jq -er .access_token
elif [[ -n "${DATABRICKS_CLIENT_ID:-}" && -n "${DATABRICKS_CLIENT_SECRET:-}" ]]; then
  mint "${DATABRICKS_HOST:?DATABRICKS_HOST required}" "$DATABRICKS_CLIENT_ID" "$DATABRICKS_CLIENT_SECRET"
elif [[ -n "${DATABRICKS_M2M_SECRET_ID:-}" ]]; then
  s=$(aws secretsmanager get-secret-value --secret-id "$DATABRICKS_M2M_SECRET_ID" \
        --region "${AWS_REGION:?AWS_REGION required}" ${AWS_PROFILE:+--profile "$AWS_PROFILE"} \
        --query SecretString --output text)
  mint "$(jq -r .host <<<"$s")" "$(jq -r .client_id <<<"$s")" "$(jq -r .client_secret <<<"$s")"
else
  echo "databricks_token.sh: set DATABRICKS_PROFILE, DATABRICKS_CLIENT_ID/SECRET or DATABRICKS_M2M_SECRET_ID" >&2
  exit 1
fi
