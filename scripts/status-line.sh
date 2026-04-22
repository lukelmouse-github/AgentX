#!/usr/bin/env bash
# AX status line — renders sedimentation progress in Claude Code's bottom bar
# Reads session state from /tmp/ax-* files written by post-tool-use.sh and ax-review.sh

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

STATE_FILE="/tmp/ax-state-${SESSION_ID}.json"
TRIGGER_FILE="/tmp/ax-trigger-${SESSION_ID}"
LOCK_FILE="/tmp/ax-review-${SESSION_ID}.lock"
DONE_FILE="/tmp/ax-done-${SESSION_ID}"

# ── Read state ──
if [ -f "$STATE_FILE" ]; then
  HEAVY_TURNS=$(jq -r '.heavy_turns // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  BRAINSTORM_COUNT=$(jq -r '.brainstorm_count // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  TOOL_COUNT=$(jq -r '.tool_count // 0' "$STATE_FILE" 2>/dev/null || echo 0)
else
  HEAVY_TURNS=0
  BRAINSTORM_COUNT=0
  TOOL_COUNT=0
fi

# ── Determine phase ──
# Phase priority: done > reviewing > debouncing > accumulating

REVIEW_RUNNING=false
if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
  REVIEW_RUNNING=true
fi

if [ -f "$DONE_FILE" ]; then
  DONE_AGO=$(( $(date +%s) - $(cat "$DONE_FILE") ))
  if [ "$DONE_AGO" -lt 300 ]; then
    RESULT=$(cat "/tmp/ax-done-result-${SESSION_ID}" 2>/dev/null || echo "done")
    if [ "$RESULT" = "skip" ]; then
      printf '\033[90mAX · nothing to save\033[0m'
    else
      printf '\033[32mAX ✓ sediment written · git diff to review\033[0m'
    fi
    exit 0
  else
    rm -f "$DONE_FILE" "/tmp/ax-done-result-${SESSION_ID}"
  fi
fi

if [ "$REVIEW_RUNNING" = "true" ]; then
  printf '\033[36mAX ⟳ reviewing transcript…\033[0m'
  exit 0
fi

if [ -f "$TRIGGER_FILE" ]; then
  TRIGGER_TIME=$(cat "$TRIGGER_FILE")
  NOW=$(date +%s)
  ELAPSED=$((NOW - TRIGGER_TIME))
  REMAINING=$((60 - ELAPSED))
  [ "$REMAINING" -lt 0 ] && REMAINING=0
  printf '\033[33mAX ● triggered · debounce %ds\033[0m' "$REMAINING"
  exit 0
fi

# ── Accumulating — show progress toward thresholds ──
if [ "$TOOL_COUNT" -eq 0 ]; then
  exit 0
fi

# Build progress indicators
HT_MAX=3
BC_MAX=3

ht_dots=""
for i in 1 2 3; do
  if [ "$HEAVY_TURNS" -ge "$i" ]; then
    ht_dots="${ht_dots}●"
  else
    ht_dots="${ht_dots}○"
  fi
done

bc_dots=""
for i in 1 2 3; do
  if [ "$BRAINSTORM_COUNT" -ge "$i" ]; then
    bc_dots="${bc_dots}●"
  else
    bc_dots="${bc_dots}○"
  fi
done

# Color: dim gray when far from trigger, brighter as closer
if [ "$HEAVY_TURNS" -ge 2 ] || [ "$BRAINSTORM_COUNT" -ge 2 ]; then
  COLOR='\033[93m'  # bright yellow — close to trigger
elif [ "$HEAVY_TURNS" -ge 1 ] || [ "$BRAINSTORM_COUNT" -ge 1 ]; then
  COLOR='\033[37m'  # white — some progress
else
  COLOR='\033[90m'  # dim gray — early stage
fi

printf "${COLOR}AX  heavy ${ht_dots}  brain ${bc_dots}\033[0m"
