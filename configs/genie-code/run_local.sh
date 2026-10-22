#!/usr/bin/env bash
# Run a task with the genie-code agent on local Docker (Colima or Docker Desktop).
#
# Usage (from the repo root):
#   DATABRICKS_CONFIG_PROFILE=<u2m-profile> configs/genie-code/run_local.sh [model] [task-path]
#
# The workspace host is read from the profile. Harbor mints a short-lived token
# from the profile on this machine for each trial and passes only that token
# into the task container.
# Env: JOBS_DIR [jobs/item1-local], JOB_NAME [genie-code-<stamp>], N_CONCURRENT [1]
set -euo pipefail

profile=${DATABRICKS_CONFIG_PROFILE:?set DATABRICKS_CONFIG_PROFILE to a Databricks CLI profile}
model=${1:-databricks/gpt-5.4-mini}
task=${2:-tasks/smoke}

host=$(databricks auth describe --profile "$profile" -o json | jq -er .details.host)
stamp=$(date -u +%Y%m%dT%H%M%SZ)

DATABRICKS_HOST="$host" DATABRICKS_CONFIG_PROFILE="$profile" \
  uv run harbor run \
  -p "$task" \
  -a genie-code \
  -m "$model" \
  -n "${N_CONCURRENT:-1}" \
  -o "${JOBS_DIR:-jobs/item1-local}" \
  --job-name "${JOB_NAME:-genie-code-$stamp}"
