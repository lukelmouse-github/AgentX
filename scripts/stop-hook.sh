#!/usr/bin/env bash
# AX Stop hook — evaluate whether the session has sedimentable knowledge
# Triggered once per turn when Claude finishes responding.
# Two-layer filter: hard metrics first (cheap), then background LLM review (expensive).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ax-log.sh"

# grep -c returns exit 1 when no match (breaks set -e), wc -l has leading spaces on macOS
count_grep() { grep -c "$1" "$2" 2>/dev/null || true; }
count_lines() { wc -l < "$1" 2>/dev/null | tr -d ' '; }
count_grep_stdin() { grep -c "$1" 2>/dev/null || true; }
count_lines_stdin() { wc -l | tr -d ' '; }

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
if [ -z "$SESSION_ID" ]; then
  ax_log "STOP: no session_id, skip"
  exit 0
fi

TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  ax_log "STOP: no transcript (path=${TRANSCRIPT_PATH}), skip"
  exit 0
fi

REVIEW_LOCK="/tmp/ax-review-${SESSION_ID}.lock"

ax_log "STOP: fired session=${SESSION_ID:0:8} cwd=${CWD}"

# ── Defaults (overridable via .ax/config in project root) ──
AX_SCORE_THRESHOLD=100
AX_WEIGHT_AGENT=30
AX_WEIGHT_EDIT=8
AX_WEIGHT_BASH=3
AX_WEIGHT_READ=1
AX_WEIGHT_BRAIN=80
AX_WEIGHT_LINES=10
AX_WINDOW_TURNS=3
AX_REVIEW_COOLDOWN=600

PROJECT_ROOT=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
AX_CONFIG="${PROJECT_ROOT}/.ax/config"
if [ -f "$AX_CONFIG" ]; then
  source "$AX_CONFIG"
  ax_log "STOP: loaded config from ${AX_CONFIG}"
fi

REAL_USER_LINES=$(grep -n '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null | grep -v '"tool_result"' | tail -"$AX_WINDOW_TURNS" | cut -d: -f1)
WINDOW_START=$(echo "$REAL_USER_LINES" | head -1)
WINDOW_START=${WINDOW_START:-0}
TOTAL_LINES=$(count_lines "$TRANSCRIPT_PATH")
TOTAL_TURNS=$(count_grep '"type":"user"' "$TRANSCRIPT_PATH")

SCORE=0
if [ "$WINDOW_START" -gt 0 ]; then
  WINDOW_FILE="/tmp/ax-window-${SESSION_ID}.tmp"
  tail -n +"$WINDOW_START" "$TRANSCRIPT_PATH" > "$WINDOW_FILE"

  W_AGENTS=$(grep -c '"name":"Agent"' "$WINDOW_FILE" 2>/dev/null || true)
  W_EDITS=$(grep -cE '"name":"(Edit|Write)"' "$WINDOW_FILE" 2>/dev/null || true)
  W_BASH=$(grep -c '"name":"Bash"' "$WINDOW_FILE" 2>/dev/null || true)
  W_READS=$(grep -c '"name":"Read"' "$WINDOW_FILE" 2>/dev/null || true)
  W_BRAIN=$(count_grep '"skill":"brainstorming"' "$WINDOW_FILE")
  W_LINES=$(count_lines "$WINDOW_FILE")

  SCORE=$(( W_AGENTS * AX_WEIGHT_AGENT + W_EDITS * AX_WEIGHT_EDIT + W_BASH * AX_WEIGHT_BASH + W_READS * AX_WEIGHT_READ + W_BRAIN * AX_WEIGHT_BRAIN + W_LINES / 100 * AX_WEIGHT_LINES ))

  ax_log "STOP: scoring agents=${W_AGENTS}(*${AX_WEIGHT_AGENT}) edits=${W_EDITS}(*${AX_WEIGHT_EDIT}) bash=${W_BASH}(*${AX_WEIGHT_BASH}) reads=${W_READS}(*${AX_WEIGHT_READ}) brain=${W_BRAIN}(*${AX_WEIGHT_BRAIN}) lines=${W_LINES}(/100*${AX_WEIGHT_LINES}) => score=${SCORE}/${AX_SCORE_THRESHOLD}"
  rm -f "$WINDOW_FILE"
else
  ax_log "STOP: no real user messages found"
fi

ax_log "STOP: metrics score=${SCORE} total_turns=${TOTAL_TURNS} total_lines=${TOTAL_LINES}"

if [ "$SCORE" -lt "$AX_SCORE_THRESHOLD" ]; then
  ax_log "STOP: score ${SCORE} < ${AX_SCORE_THRESHOLD}, skip"
  exit 0
fi

ax_log "STOP: threshold met, checking guards"

# ── Skip if review already running ──
if [ -f "$REVIEW_LOCK" ] && kill -0 "$(cat "$REVIEW_LOCK" 2>/dev/null)" 2>/dev/null; then
  ax_log "STOP: review already running (pid=$(cat "$REVIEW_LOCK")), skip"
  exit 0
fi

# ── Skip if already reviewed recently ──
DONE_FILE="/tmp/ax-done-${SESSION_ID}"
if [ -f "$DONE_FILE" ]; then
  DONE_AGO=$(( $(date +%s) - $(cat "$DONE_FILE") ))
  if [ "$DONE_AGO" -lt "$AX_REVIEW_COOLDOWN" ]; then
    ax_log "STOP: reviewed ${DONE_AGO}s ago (<600s), skip"
    exit 0
  fi
fi

# ── Skip if user already ran /ax manually ──
if grep -q '/ax' "$TRANSCRIPT_PATH" 2>/dev/null; then
  ax_log "STOP: user ran /ax manually, skip"
  exit 0
fi

ax_log "STOP: launching background review project=${PROJECT_ROOT}"

# ── Launch background review ──
nohup bash "$SCRIPT_DIR/ax-review.sh" "$SESSION_ID" "$TRANSCRIPT_PATH" "$PROJECT_ROOT" \
  > /dev/null 2>&1 &

exit 0
