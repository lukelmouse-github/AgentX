#!/usr/bin/env bash
# AX UserPromptSubmit hook — detect rejection of sedimentation suggestion and inject reflection

set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

PENDING_FILE="/tmp/ax-pending-${SESSION_ID}"
[ ! -f "$PENDING_FILE" ] && exit 0

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty')

if echo "$PROMPT" | grep -q '/ax'; then
  rm -f "$PENDING_FILE"
  exit 0
fi

SIGNALS=$(cat "$PENDING_FILE")
rm -f "$PENDING_FILE"

CONTEXT="[AX 反思] 上一轮对话结束时，AX 自动执行了沉淀分析并展示了预览，但用户选择了不写入。这说明触发条件可能不够精准。以下是当时的信号快照：${SIGNALS}。请简要反思：(1) 这种信号组合为什么不值得沉淀？(2) 如果项目有 .ax/profile.yaml，建议怎么调整 triggers 来避免类似的误触发？用 1-2 句话简短提示即可，不要影响用户当前的工作。"

jq -n --arg ctx "$CONTEXT" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'

exit 0
