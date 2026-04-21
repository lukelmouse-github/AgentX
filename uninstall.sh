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

# ── 1. Remove .claude/skills/ symlinks pointing to .ax/ ──────────────
SKILLS_DIR="${PROJECT_ROOT}/.claude/skills"
if [ -d "$SKILLS_DIR" ]; then
    for link in "$SKILLS_DIR"/*/; do
        [ -L "${link%/}" ] || continue
        target="$(readlink "${link%/}")"
        if echo "$target" | grep -q '\.ax/skills'; then
            rm "${link%/}"
            echo "[ax]   removed skill symlink: $(basename "${link%/}")"
        fi
    done
fi

# ── 2. Remove AX hook from .claude/settings.json ─────────────────────
SETTINGS="${PROJECT_ROOT}/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    python3 - "$SETTINGS" << 'PYEOF'
import json, re, sys

settings_path = sys.argv[1]

with open(settings_path) as f:
    content = f.read()

content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
settings = json.loads(content)

hooks = settings.get("hooks", {})
start_list = hooks.get("SessionStart", [])

original_len = len(start_list)
start_list = [
    entry for entry in start_list
    if not any(".ax/hooks" in h.get("command", "") for h in entry.get("hooks", []))
]

if len(start_list) < original_len:
    if start_list:
        hooks["SessionStart"] = start_list
    else:
        hooks.pop("SessionStart", None)
    if not hooks:
        settings.pop("hooks", None)
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print("[ax]   removed SessionStart hook")
else:
    print("[ax]   skip settings.json (no AX hook found)")
PYEOF
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
echo "  - docs/ai-context/ — keep or remove as you see fit"
echo ""
echo "  git add -A && git commit -m 'chore: remove AX plugin'"
