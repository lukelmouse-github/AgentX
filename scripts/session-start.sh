#!/usr/bin/env bash
# AX SessionStart hook — inject core sedimentation rules into agent context

set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)

# Clean up stale signal and pending files from previous sessions (keep current)
if [ -n "$SESSION_ID" ]; then
  for f in /tmp/ax-signals-*.jsonl; do
    [ -f "$f" ] || continue
    [ "$f" = "/tmp/ax-signals-${SESSION_ID}.jsonl" ] && continue
    rm -f "$f" 2>/dev/null || true
  done
  for f in /tmp/ax-pending-*; do
    [ -f "$f" ] || continue
    [ "$f" = "/tmp/ax-pending-${SESSION_ID}" ] && continue
    rm -f "$f" 2>/dev/null || true
  done
fi

read -r -d '' CONTEXT << 'RULES' || true
## AX Knowledge Sedimentation

完成复杂工作后（多步调试、tricky bug、发现非显而易见的约定），评估是否需要通过 `/ax:ax` 将经验沉淀到 `docs/ai-context/`、`.agents/skills/` 或 `AGENTS.md`。

不要直接写入这些知识文件。先通过 `/ax:ax` 生成预览，得到用户确认后再落盘。

如果项目尚未初始化沉淀决策脚本，可以运行 `/ax:init` 为项目生成自定义的触发策略。
RULES

CONTEXT_ESCAPED=$(printf '%s' "$CONTEXT" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | sed 's/  */ /g')

printf '{\n  "additionalContext": "%s"\n}\n' "$CONTEXT_ESCAPED"

exit 0
