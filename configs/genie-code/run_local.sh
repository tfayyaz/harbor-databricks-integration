#!/usr/bin/env bash
# Run a task with the genie-code agent on local Docker (Colima or Docker Desktop).
#
# Usage (from the repo root):
#   DATABRICKS_CONFIG_PROFILE=<u2m-profile> configs/genie-code/run_local.sh [model] [task-path]
#   DATABRICKS_HOST=<url> DATABRICKS_CLIENT_ID=<id> DATABRICKS_CLIENT_SECRET=<secret> \
#     configs/genie-code/run_local.sh [model] [task-path]          # OAuth M2M, e.g. on EC2
#
# With a profile, the workspace host is read from it. The agent mints a
# short-lived token on this machine for each trial (from the profile, or from
# the M2M credentials) and passes only that token into the task container.
# Env: JOBS_DIR [jobs/item1-local], JOB_NAME [genie-code-<stamp>], N_CONCURRENT [1],
#      HARBOR [uv run harbor]
set -euo pipefail

model=${1:-databricks/gpt-5.4-mini}
task=${2:-tasks/smoke}

if [[ -z ${DATABRICKS_HOST:-} ]]; then
  profile=${DATABRICKS_CONFIG_PROFILE:?set DATABRICKS_CONFIG_PROFILE, or DATABRICKS_HOST with M2M credentials}
  DATABRICKS_HOST=$(databricks auth describe --profile "$profile" -o json | jq -er .details.host)
fi
export DATABRICKS_HOST
stamp=$(date -u +%Y%m%dT%H%M%SZ)

${HARBOR:-uv run harbor} run \
  -p "$task" \
  -a genie-code \
  -m "$model" \
  -n "${N_CONCURRENT:-1}" \
  -o "${JOBS_DIR:-jobs/item1-local}" \
  --job-name "${JOB_NAME:-genie-code-$stamp}"
