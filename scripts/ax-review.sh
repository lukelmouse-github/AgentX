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

REVIEW_PROMPT="You are a project knowledge curator. Below is an extracted conversation from a coding session.

Read the file at ${EXTRACT_FILE} using the Read tool.

Decide if it contains reusable project knowledge worth saving. Worth saving means:
- Non-trivial architectural decisions or design patterns discovered through exploration
- Debugging approaches that required trial-and-error (root cause + solution)
- Integration patterns, API gotchas, or environment-specific workarounds
- Reusable workflows that took multiple steps to figure out

NOT worth saving:
- Simple Q&A, obvious fixes, standard library usage
- One-off task context that won't recur
- Content already documented in existing project files

If something is worth saving, write it to the appropriate path under ${PROJECT_ROOT}:
- Architecture/design knowledge → docs/ai-context/{topic}.md
- Reusable workflows → .agents/skills/{name}/SKILL.md
- Module-specific context → {module}/AGENTS.md

Before writing:
1. Use Grep to check if similar content already exists — update instead of duplicating
2. Keep each file under 200 lines
3. If AGENTS.md does not exist at project root, create it with a minimal template

If nothing is worth saving, respond with exactly: Nothing to save."

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
