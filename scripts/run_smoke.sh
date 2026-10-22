#!/usr/bin/env bash
# Run the smoke task once per agent, one agent at a time.
# Usage: run_smoke.sh <claude-code|codex|pi|opencode|all>... [-- extra harbor run args]
# Requires DATABRICKS_HOST and a token source understood by databricks_token.sh.
# Prints one "agent=... job=... reward=..." line per agent; exits 1 if any failed.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/.." && pwd)
agents=(); while [[ $# -gt 0 && $1 != -- ]]; do agents+=("$1"); shift; done
[[ ${1:-} == -- ]] && shift
[[ ${#agents[@]} -eq 0 || ${agents[0]} == all ]] && agents=(claude-code codex pi opencode)
jobs_dir=${JOBS_DIR:-$root/jobs}; export JOBS_DIR=$jobs_dir
tag=${RUN_TAG:-$(date -u +%Y%m%dT%H%M%SZ)}

status=0
for agent in "${agents[@]}"; do
  job="item2-$agent-$tag"
  "$here/run_local.sh" "$root/configs/model-serving/$agent.yaml" --path "${TASK_PATH:-$root/tasks/smoke}" \
    --job-name "$job" "$@" >"${TMPDIR:-/tmp}/$job.out" 2>&1 || true
  reward=$( (jq -r '[.. | objects | .reward? | numbers] | first // "none"' \
    "$jobs_dir"/"$job"/*/result.json 2>/dev/null || true) | head -1)
  error=$( (jq -r '.exception_info.exception_type // empty' \
    "$jobs_dir"/"$job"/*/result.json 2>/dev/null || true) | head -1)
  echo "agent=$agent job=$job reward=${reward:-none}${error:+ exception=$error}"
  [[ $reward == 1 || $reward == 1.0 ]] || status=1
done
exit $status
