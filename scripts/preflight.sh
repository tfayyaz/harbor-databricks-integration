#!/usr/bin/env bash
# Fail fast if a Model Serving endpoint can't answer over the API its agent uses.
# Usage: preflight.sh <endpoint-name> [max-seconds]
#   *claude* endpoints -> Anthropic Messages; others -> OpenAI Responses with a tool call.
# Requires DATABRICKS_HOST and a token source understood by databricks_token.sh.
set -euo pipefail

model=${1:?usage: preflight.sh <endpoint-name> [max-seconds]}
budget=${2:-60}
host=${DATABRICKS_HOST:?DATABRICKS_HOST required}; host=${host%/}
token=$("$(dirname "$0")/databricks_token.sh")

if [[ $model == *claude* ]]; then
  url="$host/serving-endpoints/anthropic/v1/messages"
  body=$(jq -n --arg m "$model" '{model:$m,max_tokens:16,messages:[{role:"user",content:"Reply OK"}]}')
else
  # Agents need tool calls, so check them, not just plain text.
  url="$host/serving-endpoints/responses"
  body=$(jq -n --arg m "$model" '{model:$m,input:"Call ping.",max_output_tokens:256,tool_choice:"required",
    tools:[{type:"function",name:"ping",parameters:{type:"object",properties:{}}}]}')
fi

read -r code secs < <(curl -sS -o /dev/null -w '%{http_code} %{time_total}\n' --max-time "$budget" \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
  -H 'x-databricks-disable-beta-headers: true' -d "$body" "$url" || echo "000 $budget")
echo "model=$model http=$code seconds=$secs url=${url#"$host"}"
[[ $code == 200 ]]
