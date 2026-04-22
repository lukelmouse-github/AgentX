#!/usr/bin/env bash
# AX background review — invoke claude -p to judge and sediment project knowledge
set -euo pipefail

SESSION_ID="$1"
TRANSCRIPT_PATH="$2"
PROJECT_ROOT="$3"

LOCK_FILE="/tmp/ax-review-${SESSION_ID}.lock"

cleanup() { rm -f "$LOCK_FILE"; }
trap cleanup EXIT

echo $$ > "$LOCK_FILE"

REVIEW_PROMPT="You are a project knowledge curator. Read the conversation transcript at ${TRANSCRIPT_PATH} and decide if it contains knowledge worth saving to the project repository.

Focus on: was a non-trivial approach used to complete a task that required trial and error, or changing course due to experiential findings, or did the user discover important architecture/design/debugging knowledge worth preserving?

If something is worth saving, write it directly to the appropriate path under the project root (${PROJECT_ROOT}):
- Architecture/design knowledge → docs/ai-context/{topic}.md
- Reusable workflows → .agents/skills/{name}/SKILL.md
- Module-specific context → {module}/AGENTS.md

Rules:
- Each file under 200 lines
- Check for existing files before creating duplicates (use Grep to search for keywords first)
- Update existing files when content overlaps rather than creating new ones
- Use @ references to link related docs
- If AGENTS.md does not exist at project root, create it with a minimal template

If nothing is worth saving, just say 'Nothing to save.' and stop."

cd "$PROJECT_ROOT"

claude -p "$REVIEW_PROMPT" \
  --bare \
  --allowedTools "Read,Write,Edit,Bash,Grep,Glob" \
  --dangerously-skip-permissions \
  --max-budget-usd 2.00 \
  > /dev/null 2>&1 || true
