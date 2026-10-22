#!/usr/bin/env bash
# Run the smoke task on a throwaway EC2 worker with Databricks OAuth M2M.
# Usage (from the repo root): ec2_smoke.sh [agent ...]   (default: all four)
# Env: as ec2_run.sh, plus DATABRICKS_HOST and DATABRICKS_M2M_SECRET_ID (the
# Secrets Manager id of a JSON {host, client_id, client_secret}).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f $root/.env.local ]]; then set -a; . "$root/.env.local"; set +a; fi
agents=${*:-claude-code codex pi opencode}
host=${DATABRICKS_HOST:?DATABRICKS_HOST required}
secret=${DATABRICKS_M2M_SECRET_ID:?DATABRICKS_M2M_SECRET_ID required}

# The worker uses public npm; a laptop's npm mirror isn't passed through.
cd "$root"
WORKER_ENV="DATABRICKS_HOST=$host DATABRICKS_M2M_SECRET_ID=$secret RUN_TAG=ec2-\$(date -u +%Y%m%dT%H%M%SZ) ${WORKER_ENV:-}" \
  exec scripts/ec2_run.sh "scripts/run_smoke.sh $agents" agents scripts configs tasks pyproject.toml
