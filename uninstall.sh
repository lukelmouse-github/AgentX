#!/usr/bin/env bash
# AX — Uninstall script
#
# Removes AX from a project. Does NOT delete AGENTS.md/CLAUDE.md or auto-commit.
#
# Usage:
#   bash .ax/uninstall.sh
#   # Or specify a project path
#   bash .ax/uninstall.sh /path/to/project
set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || {
    echo "[ax] Error: directory not found: ${1:-$(pwd)}"
    exit 1
}

AX_DIR="${PROJECT_ROOT}/.ax"

if [ ! -d "$AX_DIR" ]; then
    echo "[ax] AX is not installed in ${PROJECT_ROOT}"
    exit 0
fi

echo "[ax] Uninstalling AX from: ${PROJECT_ROOT}"

# ── 1. Remove .claude/skills/ symlinks pointing to AX adapters ───────
SKILLS_DIR="${PROJECT_ROOT}/.claude/skills"
if [ -d "$SKILLS_DIR" ]; then
    for link in "$SKILLS_DIR"/*; do
        [ -L "$link" ] || continue
        target="$(readlink "$link")"
        if echo "$target" | grep -Eq '^\.\./\.\./\.ax/skills/|^\.\./\.\./\.agents/skills/'; then
            rm "$link"
            echo "[ax]   removed skill symlink: $(basename "$link")"
        fi
    done
fi

# ── 2. Remove AX hook from .claude/settings.json ─────────────────────
SETTINGS="${PROJECT_ROOT}/.claude/settings.json"
if [ -f "$SETTINGS" ] && [ -f "${AX_DIR}/scripts/manage_claude_settings.py" ]; then
    python3 "${AX_DIR}/scripts/manage_claude_settings.py" remove "$SETTINGS" "bash .ax/hooks/session-start"
fi

# ── 3. Remove .ax/ directory ─────────────────────────────────────────
rm -rf "$AX_DIR"
echo "[ax]   removed .ax/"

# ── 4. Remove CLAUDE.md if it's a symlink to AGENTS.md ───────────────
CLAUDE_MD="${PROJECT_ROOT}/CLAUDE.md"
if [ -L "$CLAUDE_MD" ]; then
    target="$(readlink "$CLAUDE_MD")"
    if [ "$target" = "AGENTS.md" ]; then
        rm "$CLAUDE_MD"
        echo "[ax]   removed CLAUDE.md symlink"
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────
echo ""
echo "[ax] AX has been removed."
echo "[ax] Please manually review:"
echo "  - AGENTS.md — remove the '知识沉淀' section and @.ax/RULES.md references"
echo "  - CLAUDE.md — remove AX-related content if it was a real file"
echo "  - .agents/skills/ and docs/ai-context/ — keep or remove as you see fit"
echo ""
echo "  git add -A && git commit -m 'chore: remove AX plugin'"
