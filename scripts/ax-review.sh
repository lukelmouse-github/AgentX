#!/usr/bin/env bash
# AX background review — invoke claude -p to judge and sediment project knowledge
set -euo pipefail

SESSION_ID="$1"
TRANSCRIPT_PATH="$2"
PROJECT_ROOT="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ax-log.sh"

LOCK_FILE="/tmp/ax-review-${SESSION_ID}.lock"
DONE_FILE="/tmp/ax-done-${SESSION_ID}"
DONE_RESULT_FILE="/tmp/ax-done-result-${SESSION_ID}"

cleanup() { rm -f "$LOCK_FILE"; }
trap cleanup EXIT

echo $$ > "$LOCK_FILE"

ax_log "REVIEW: started session=${SESSION_ID:0:8} transcript=${TRANSCRIPT_PATH} project=${PROJECT_ROOT}"

# Extract user+assistant text from transcript to reduce noise
EXTRACT_FILE="/tmp/ax-extract-${SESSION_ID}.txt"
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg_type = d.get('type')
        if msg_type not in ('user', 'assistant'):
            continue
        msg = d.get('message', {})
        content = msg.get('content', [])
        if isinstance(content, str):
            texts = [content]
        elif isinstance(content, list):
            texts = [c.get('text', '') for c in content if isinstance(c, dict) and c.get('type') == 'text']
        else:
            continue
        for text in texts:
            text = text.strip()
            if not text:
                continue
            if len(text) > 1000:
                text = text[:1000] + '...[truncated]'
            print(f'[{msg_type}] {text}')
" "$TRANSCRIPT_PATH" > "$EXTRACT_FILE" 2>/dev/null || true

EXTRACT_LINES=$(wc -l < "$EXTRACT_FILE" 2>/dev/null | tr -d ' ')
ax_log "REVIEW: extracted ${EXTRACT_LINES} lines"

if [ "$EXTRACT_LINES" -lt 5 ]; then
  ax_log "REVIEW: too few lines (${EXTRACT_LINES}<5), skip"
  date +%s > "$DONE_FILE"
  echo "skip" > "$DONE_RESULT_FILE"
  rm -f "$EXTRACT_FILE"
  exit 0
fi

REVIEW_PROMPT="你是项目知识管理员。下面是一段编码会话的提取内容。

用 Read 工具读取 ${EXTRACT_FILE} 文件。

判断其中是否包含值得沉淀的可复用项目知识。值得沉淀的：
- 通过探索发现的非显而易见的架构决策或设计模式
- 经过反复排查才定位的 bug（根因 + 解法）
- 集成模式、API 陷阱、环境相关的 workaround
- 需要多步操作才摸索出来的可复用流程

不值得沉淀的：
- 简单问答、显而易见的修复、标准库用法
- 一次性任务上下文，不会再出现
- 项目文件中已有记录的内容

如果有值得沉淀的内容，按以下规则放置和更新。

## 放置规则

| 知识类型 | 目标路径 | 举例 |
|---------|---------|------|
| 架构知识、技术选型、全局约定、核心链路 | docs/ai-context/{topic}.md | 整体架构、线程模型、构建约定、核心数据流 |
| 代码相关：模块 API 细节、陷阱、模式 | {module}/AGENTS.md | 某个包的工作原理、隐含约束、调用模式 |
| 可复用的多步流程 | .agents/skills/{name}/SKILL.md | 排障流程、部署步骤、迁移方案 |

代码相关的知识（某个类、模块、包）必须放到对应代码目录的 AGENTS.md，不要放到 docs/ai-context/。
docs/ai-context/ 只放跨模块的架构知识、全局约定和核心链路。

## 更新规则

写入任何文件之前：

1. 用 Glob 列出 docs/ai-context/、.agents/skills/ 以及相关 {module}/ 目录下已有的 *.md 文件。
2. 读取文件名可能与新知识重叠的已有文件。
3. 如果已有相关文件且不超过 180 行，追加到该文件，不要新建。
4. 如果已有相关文件但超过 180 行，拆分：保持原文件聚焦原有主题，新主题写入新文件。
5. 单个文件绝不超过 200 行。如果追加后会超过 200 行，先拆分再写入。
6. 如果没有相关文件，新建。
7. 如果项目根目录没有 AGENTS.md，用最小模板创建一个。

## 输出

如果没有值得沉淀的内容，只回复：Nothing to save."

cd "$PROJECT_ROOT"

# Load project config
AX_REVIEW_INSTRUCTIONS=""
AX_REVIEW_LANGUAGE="中文"
AX_CONFIG="${PROJECT_ROOT}/.ax/config"
if [ -f "$AX_CONFIG" ]; then
  source "$AX_CONFIG"
fi

REVIEW_PROMPT="${REVIEW_PROMPT}

## Output language

All generated markdown, skills, and documentation must be written in ${AX_REVIEW_LANGUAGE}."

if [ -n "$AX_REVIEW_INSTRUCTIONS" ]; then
  REVIEW_PROMPT="${REVIEW_PROMPT}

## Project-specific instructions

${AX_REVIEW_INSTRUCTIONS}"
  ax_log "REVIEW: appended custom instructions (${#AX_REVIEW_INSTRUCTIONS} chars)"
fi

ax_log "REVIEW: invoking claude -p --model sonnet"

REVIEW_OUTPUT=$(claude -p "$REVIEW_PROMPT" \
  --model sonnet \
  --bare \
  --allowedTools "Read,Write,Edit,Bash,Grep,Glob" \
  --dangerously-skip-permissions \
  --max-budget-usd 1.00 \
  2>/dev/null) || true

date +%s > "$DONE_FILE"
if printf '%s' "$REVIEW_OUTPUT" | grep -qi 'nothing to save'; then
  echo "skip" > "$DONE_RESULT_FILE"
  ax_log "REVIEW: completed — nothing to save"
else
  echo "done" > "$DONE_RESULT_FILE"
  CHANGES=$(cd "$PROJECT_ROOT" && git diff --stat HEAD -- '*.md' '.agents/skills/' 2>/dev/null || true)
  UNTRACKED=$(cd "$PROJECT_ROOT" && git ls-files --others --exclude-standard -- '*.md' '.agents/skills/' 2>/dev/null || true)
  if [ -n "$CHANGES" ]; then
    ax_log "REVIEW: completed — changes:"
    echo "$CHANGES" | while IFS= read -r line; do ax_log "REVIEW:   $line"; done
  fi
  if [ -n "$UNTRACKED" ]; then
    ax_log "REVIEW: completed — new files:"
    echo "$UNTRACKED" | while IFS= read -r line; do ax_log "REVIEW:   $line"; done
  fi
  if [ -z "$CHANGES" ] && [ -z "$UNTRACKED" ]; then
    ax_log "REVIEW: completed — sediment written (no ax-managed file changes detected)"
  fi
fi

rm -f "$EXTRACT_FILE"
