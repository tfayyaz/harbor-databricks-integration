#!/usr/bin/env bash
# Run a Harbor job config that uses Databricks Model Serving.
# Usage: run_local.sh <job.yaml> [harbor run args...]   e.g. --path tasks/smoke
# Renders __DATABRICKS_HOST__ (Harbor expands ${VAR} only when it is the whole
# value) and puts agents/ on PYTHONPATH. Agents mint their own token per trial
# through databricks_token.sh, so export its token source (DATABRICKS_PROFILE
# or the M2M variables). Job outputs go to $JOBS_DIR (default jobs/).
set -euo pipefail

src=${1:?usage: run_local.sh <job.yaml> [harbor run args...]}; shift
root=$(cd "$(dirname "$0")/.." && pwd)
host=${DATABRICKS_HOST:?DATABRICKS_HOST required, e.g. https://<workspace>.cloud.databricks.com}
export DATABRICKS_HOST=${host%/}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/harbor-job-XXXXXX")
trap 'rm -rf "$tmp"' EXIT
config=$tmp/job.yaml  # Harbor picks the parser from the file extension
sed "s#__DATABRICKS_HOST__#$DATABRICKS_HOST#g" "$src" > "$config"

export PYTHONPATH="$root/agents${PYTHONPATH:+:$PYTHONPATH}"
${HARBOR:-uv run --project "$root" harbor} run --config "$config" \
  --jobs-dir "${JOBS_DIR:-$root/jobs}" --yes "$@"
