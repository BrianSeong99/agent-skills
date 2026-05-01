#!/usr/bin/env bash
# Dispatch a single prompt to local Ollama. Returns response on stdout.
# Exit 0 = success, exit 1 = transport / model / empty-response failure.
# Usage: dispatch-ollama.sh "<prompt>"  OR  echo "<prompt>" | dispatch-ollama.sh
# Env:   OLLAMA_URL (default http://localhost:11434)
#        OLLAMA_MODEL (default gemma3:4b)
#        OLLAMA_TIMEOUT_S (default 30)
set -euo pipefail

prompt="${1:-}"
if [ -z "$prompt" ]; then
  prompt=$(cat)
fi
if [ -z "$prompt" ]; then
  echo "dispatch-ollama: empty prompt" >&2
  exit 2
fi

url="${OLLAMA_URL:-http://localhost:11434}/api/generate"
model="${OLLAMA_MODEL:-gemma3:4b}"
timeout="${OLLAMA_TIMEOUT_S:-30}"

body=$(jq -nc --arg m "$model" --arg p "$prompt" '{model:$m, prompt:$p, stream:false}')

resp=$(curl -s --max-time "$timeout" -X POST "$url" -H 'Content-Type: application/json' -d "$body") || {
  echo "dispatch-ollama: curl failed (timeout=${timeout}s, url=$url)" >&2
  exit 1
}

# Ollama error payloads come back as {"error": "..."}
err=$(printf '%s' "$resp" | jq -r '.error // empty' 2>/dev/null || true)
if [ -n "$err" ]; then
  echo "dispatch-ollama: ollama error: $err" >&2
  exit 1
fi

text=$(printf '%s' "$resp" | jq -r '.response // empty' 2>/dev/null || true)
if [ -z "$text" ]; then
  echo "dispatch-ollama: empty response from $model" >&2
  exit 1
fi

printf '%s\n' "$text"
