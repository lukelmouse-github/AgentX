#!/usr/bin/env bash
# AX Stop hook — evaluate sedimentation using profile + accumulated signals

set -euo pipefail

INPUT=$(cat)

STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  exit 0
fi

ALREADY_AXED=$(grep -c '/ax' "$TRANSCRIPT" 2>/dev/null || true)
: "${ALREADY_AXED:=0}"
if [ "$ALREADY_AXED" -gt 0 ]; then
  exit 0
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PROFILE="${PROJECT_ROOT}/.ax/profile.yaml"
SIGNAL_FILE="/tmp/ax-signals-${SESSION_ID}.jsonl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RESULT=$(python3 "${SCRIPT_DIR}/eval_profile.py" "$PROFILE" "$SIGNAL_FILE" "$TRANSCRIPT" 2>/dev/null) || RESULT="false"

if [ "$RESULT" != "true" ]; then
  exit 0
fi

# Write pending marker for UserPromptSubmit rejection detection
PENDING_FILE="/tmp/ax-pending-${SESSION_ID}"
if [ -f "$SIGNAL_FILE" ]; then
  cp "$SIGNAL_FILE" "$PENDING_FILE"
else
  echo '{"source":"transcript_fallback"}' > "$PENDING_FILE"
fi

if [ -f "$PROFILE" ]; then
  REASON="[AX] 项目沉淀 profile 判定本轮对话包含值得沉淀的工作。请立即执行 /ax:ax 流程：分析当前对话，提取值得沉淀的知识，生成预览并展示给用户确认。用户确认后写入，拒绝则跳过。"
else
  REASON="[AX] 本轮对话的工具使用达到沉淀评估阈值。请立即执行 /ax:ax 流程：分析当前对话，提取值得沉淀的知识，生成预览并展示给用户确认。用户确认后写入，拒绝则跳过。提示：可以运行 /ax:init 为项目生成更精准的自定义评估策略。"
fi

printf '%s\n' "$(jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}')"

exit 0
