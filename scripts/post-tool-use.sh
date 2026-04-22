#!/usr/bin/env bash
# AX PostToolUse hook — track signals, detect trigger conditions, launch background review
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

STATE_FILE="/tmp/ax-state-${SESSION_ID}.json"
TRIGGER_FILE="/tmp/ax-trigger-${SESSION_ID}"
REVIEW_LOCK="/tmp/ax-review-${SESSION_ID}.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Derive brainstorm count from transcript (source of truth, no +1 needed) ──
BRAINSTORM_COUNT=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  BRAINSTORM_COUNT=$(grep -c '"skill":"brainstorming"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
fi

# ── Heavy turns: read previous state, update on turn boundary ──
TURN_TOOL_COUNT=0
HEAVY_TURNS=0
LAST_USERS=0

if [ -f "$STATE_FILE" ]; then
  TURN_TOOL_COUNT=$(jq -r '.turn_tool_count // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  HEAVY_TURNS=$(jq -r '.heavy_turns // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  LAST_USERS=$(jq -r '.last_transcript_users // 0' "$STATE_FILE" 2>/dev/null || echo 0)
fi

TURN_TOOL_COUNT=$((TURN_TOOL_COUNT + 1))

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  CURRENT_USERS=$(grep -c '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
  if [ "$CURRENT_USERS" -gt "$LAST_USERS" ]; then
    if [ "$TURN_TOOL_COUNT" -gt 1 ] && [ "$((TURN_TOOL_COUNT - 1))" -ge 10 ]; then
      HEAVY_TURNS=$((HEAVY_TURNS + 1))
    fi
    TURN_TOOL_COUNT=1
    LAST_USERS=$CURRENT_USERS
  fi
fi

# ── Save state ──
jq -nc \
  --argjson ttc "$TURN_TOOL_COUNT" \
  --argjson ht "$HEAVY_TURNS" \
  --argjson bc "$BRAINSTORM_COUNT" \
  --argjson lu "$LAST_USERS" \
  '{turn_tool_count:$ttc, heavy_turns:$ht, brainstorm_count:$bc, last_transcript_users:$lu}' \
  > "$STATE_FILE"

# ── Check trigger conditions (OR) ──
TRIGGERED=false
[ "$BRAINSTORM_COUNT" -ge 3 ] && TRIGGERED=true
[ "$HEAVY_TURNS" -ge 3 ] && TRIGGERED=true

# ── Debounce logic ──
NOW=$(date +%s)

if [ "$TRIGGERED" = "true" ]; then
  echo "$NOW" > "$TRIGGER_FILE"
  exit 0
fi

if [ ! -f "$TRIGGER_FILE" ]; then
  exit 0
fi

TRIGGER_TIME=$(cat "$TRIGGER_FILE")
ELAPSED=$((NOW - TRIGGER_TIME))

if [ "$ELAPSED" -lt 60 ]; then
  exit 0
fi

# ── Debounce expired — launch review ──

if [ -f "$REVIEW_LOCK" ] && kill -0 "$(cat "$REVIEW_LOCK" 2>/dev/null)" 2>/dev/null; then
  exit 0
fi

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  if grep -q '/ax' "$TRANSCRIPT_PATH" 2>/dev/null; then
    rm -f "$TRIGGER_FILE"
    exit 0
  fi
fi

PROJECT_ROOT=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null || echo "$CWD")

nohup bash "$SCRIPT_DIR/ax-review.sh" "$SESSION_ID" "$TRANSCRIPT_PATH" "$PROJECT_ROOT" \
  > /dev/null 2>&1 &

jq -nc '{turn_tool_count:0, heavy_turns:0, brainstorm_count:0, last_transcript_users:0}' \
  > "$STATE_FILE"
rm -f "$TRIGGER_FILE"

exit 0
