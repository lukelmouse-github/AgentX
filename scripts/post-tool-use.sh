#!/usr/bin/env bash
# AX PostToolUse hook — track signals, detect trigger conditions, launch background review
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
SKILL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty')
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

STATE_FILE="/tmp/ax-state-${SESSION_ID}.json"
TRIGGER_FILE="/tmp/ax-trigger-${SESSION_ID}"
REVIEW_LOCK="/tmp/ax-review-${SESSION_ID}.lock"
MUTEX_DIR="/tmp/ax-mutex-${SESSION_ID}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Acquire lock (mkdir is atomic on all POSIX systems including macOS) ──
RETRIES=0
while ! mkdir "$MUTEX_DIR" 2>/dev/null; do
  RETRIES=$((RETRIES + 1))
  [ "$RETRIES" -gt 50 ] && exit 0  # give up after ~5s
  sleep 0.1
done
trap 'rmdir "$MUTEX_DIR" 2>/dev/null' EXIT

# ── Initialize or read state ──
if [ -f "$STATE_FILE" ]; then
  STATE=$(cat "$STATE_FILE")
else
  STATE='{"tool_count":0,"turn_tool_count":0,"heavy_turns":0,"brainstorm_count":0,"last_transcript_users":0}'
fi

TOOL_COUNT=$(printf '%s' "$STATE" | jq -r '.tool_count')
TURN_TOOL_COUNT=$(printf '%s' "$STATE" | jq -r '.turn_tool_count')
HEAVY_TURNS=$(printf '%s' "$STATE" | jq -r '.heavy_turns')
BRAINSTORM_COUNT=$(printf '%s' "$STATE" | jq -r '.brainstorm_count')
LAST_USERS=$(printf '%s' "$STATE" | jq -r '.last_transcript_users')

# ── Update counters ──
TOOL_COUNT=$((TOOL_COUNT + 1))
TURN_TOOL_COUNT=$((TURN_TOOL_COUNT + 1))

# Detect new turn: count user messages in transcript
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

# Detect brainstorming skill
if [ "$TOOL_NAME" = "Skill" ] && printf '%s' "$SKILL_NAME" | grep -qi 'brainstorming'; then
  BRAINSTORM_COUNT=$((BRAINSTORM_COUNT + 1))
fi

# ── Save state ──
jq -nc \
  --argjson tc "$TOOL_COUNT" \
  --argjson ttc "$TURN_TOOL_COUNT" \
  --argjson ht "$HEAVY_TURNS" \
  --argjson bc "$BRAINSTORM_COUNT" \
  --argjson lu "$LAST_USERS" \
  '{tool_count:$tc, turn_tool_count:$ttc, heavy_turns:$ht, brainstorm_count:$bc, last_transcript_users:$lu}' \
  > "$STATE_FILE"

# ── Release lock before potentially long operations ──
rmdir "$MUTEX_DIR" 2>/dev/null
trap - EXIT

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

# Not triggered — but check if debounce expired
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

jq -nc '{tool_count:0, turn_tool_count:0, heavy_turns:0, brainstorm_count:0, last_transcript_users:0}' \
  > "$STATE_FILE"
rm -f "$TRIGGER_FILE"

exit 0
