#!/usr/bin/env bash
# AX PostToolUse hook — accumulate tool-use signals for sedimentation evaluation

set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

SIGNAL_FILE="/tmp/ax-signals-${SESSION_ID}.jsonl"

jq -nc \
  --arg tool "$TOOL_NAME" \
  --arg path "$FILE_PATH" \
  --arg cmd "$COMMAND" \
  '{tool: $tool, path: $path, cmd: $cmd}' >> "$SIGNAL_FILE"

exit 0
