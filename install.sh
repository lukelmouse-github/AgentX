#!/usr/bin/env bash
# AX — One-line project installer
#
# Installs AX into a project so that every teammate gets it after git pull.
# Everything lives inside the project repo — no global config needed.
#
# Usage:
#   # Run from inside the target project
#   curl -fsSL https://raw.githubusercontent.com/anthropics/ax/main/install.sh | bash
#
#   # Or specify a project path
#   curl -fsSL https://raw.githubusercontent.com/anthropics/ax/main/install.sh | bash -s -- /path/to/project
set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || {
    echo "[ax] Error: directory not found: ${1:-$(pwd)}"
    exit 1
}

if [ ! -d "${PROJECT_ROOT}/.git" ]; then
    echo "[ax] Error: ${PROJECT_ROOT} is not a git repository"
    exit 1
fi

echo "[ax] Installing AX into: ${PROJECT_ROOT}"

AX_DIR="${PROJECT_ROOT}/.ax"

# ── 1. Clone / update AX into .ax/ ────────────────────────────────────
if [ -d "${AX_DIR}/.git" ]; then
    echo "[ax] Updating .ax/ ..."
    git -C "$AX_DIR" pull --ff-only --quiet 2>/dev/null || true
else
    if [ -d "$AX_DIR" ]; then
        BACKUP="${AX_DIR}.bak.$(date +%Y%m%d%H%M%S)"
        cp -r "$AX_DIR" "$BACKUP"
        echo "[ax] Backed up existing .ax/ to $(basename "$BACKUP")/"
        rm -rf "$AX_DIR"
    fi
    echo "[ax] Cloning AX into .ax/ ..."
    git clone --quiet --depth 1 https://github.com/anthropics/ax.git "$AX_DIR"
    rm -rf "${AX_DIR}/.git"
    echo "[ax] Embedded AX source (git history removed)"
fi

# ── 2. Set up .claude/skills/ symlinks ────────────────────────────────
SKILLS_DIR="${PROJECT_ROOT}/.claude/skills"
mkdir -p "$SKILLS_DIR"

for skill_dir in "${AX_DIR}/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    target="${SKILLS_DIR}/${skill_name}"
    rel_path="../../.ax/skills/${skill_name}"
    if [ -L "$target" ]; then
        rm "$target"
    elif [ -e "$target" ]; then
        echo "[ax]   skip skill: ${skill_name} (exists, not a symlink)"
        echo "[ax]   ⚠ /${skill_name} will use your existing skill, not AX's. To use AX's, rename or remove ${target}/"
        continue
    fi
    ln -s "$rel_path" "$target"
    echo "[ax]   linked skill: ${skill_name}"
done

# ── 3. Add SessionStart hook to .claude/settings.json ─────────────────
# Only appends AX hook — never modifies or removes existing hooks.
SETTINGS="${PROJECT_ROOT}/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

python3 - "$SETTINGS" << 'PYEOF'
import json, re, sys

settings_path = sys.argv[1]

with open(settings_path) as f:
    content = f.read()

# Strip // and /* */ comments for JSON5 compatibility
content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
settings = json.loads(content)

hooks = settings.setdefault("hooks", {})

start_cmd = "bash .ax/hooks/session-start"

# Check if AX hook already exists
start_list = hooks.setdefault("SessionStart", [])
already_exists = any(
    ".ax/hooks" in h.get("command", "")
    for entry in start_list
    for h in entry.get("hooks", [])
)

if already_exists:
    print("[ax]   skip hook: SessionStart (already configured)")
else:
    start_list.append({"matcher": "", "hooks": [{"type": "command", "command": start_cmd}]})
    print("[ax]   added hook: SessionStart")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF

# ── 4. Create AGENTS.md + CLAUDE.md if missing ───────────────────────
# Pre-create docs/ai-context/ so agent can write to it immediately
DOCS_DIR="${PROJECT_ROOT}/docs/ai-context"
if [ ! -d "$DOCS_DIR" ]; then
    mkdir -p "$DOCS_DIR"
    touch "${DOCS_DIR}/.gitkeep"
    echo "[ax]   created docs/ai-context/"
fi

AGENTS_MD="${PROJECT_ROOT}/AGENTS.md"
if [ ! -f "$AGENTS_MD" ]; then
    PROJECT_NAME="$(basename "$PROJECT_ROOT")"
    cat > "$AGENTS_MD" << MDEOF
# ${PROJECT_NAME}

## Instructions

### AGENTS.md 读取规则

修改或设计涉及某目录的代码前，**必须**：

1. 检查该目录是否存在 AGENTS.md，若存在则先阅读
2. 检查父目录是否存在 AGENTS.md，若存在则先阅读
3. 阅读 AGENTS.md 中 @ 引用的相关文档

### 知识沉淀

完成复杂任务后，主动判断是否沉淀：skill → .agents/skills/，知识 → docs/ai-context/，模块 → AGENTS.md。
发现已有文档过时时立即更新。详见 @.ax/RULES.md。

## Quick Start

\`\`\`bash
# TODO: add build/test commands
\`\`\`

## Architecture

TODO: high-level architecture summary.

## Deep Dive Docs

<!-- AX will auto-append @ references here -->
MDEOF
    echo "[ax]   created AGENTS.md"
else
    # Ensure existing AGENTS.md has @.ax/RULES.md reference
    if ! grep -q '@\.ax/RULES\.md' "$AGENTS_MD" 2>/dev/null; then
        cat >> "$AGENTS_MD" << 'APPENDEOF'

### 知识沉淀

完成复杂任务后，主动判断是否沉淀：skill → .agents/skills/，知识 → docs/ai-context/，模块 → AGENTS.md。
发现已有文档过时时立即更新。详见 @.ax/RULES.md。
APPENDEOF
        echo "[ax]   appended sedimentation rules to existing AGENTS.md"
    else
        echo "[ax]   skip AGENTS.md (already has @.ax/RULES.md reference)"
    fi
fi

CLAUDE_MD="${PROJECT_ROOT}/CLAUDE.md"
if [ ! -f "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ]; then
    ln -s AGENTS.md "$CLAUDE_MD"
    echo "[ax]   created CLAUDE.md → AGENTS.md symlink"
elif [ -f "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ]; then
    # CLAUDE.md is a real file (not symlink) — append sedimentation rules if missing
    if ! grep -q '@\.ax/RULES\.md' "$CLAUDE_MD" 2>/dev/null; then
        cat >> "$CLAUDE_MD" << 'APPENDEOF'

### 知识沉淀

完成复杂任务后，主动判断是否沉淀：skill → .agents/skills/，知识 → docs/ai-context/，模块 → AGENTS.md。
发现已有文档过时时立即更新。详见 @.ax/RULES.md。
APPENDEOF
        echo "[ax]   appended sedimentation rules to existing CLAUDE.md"
    else
        echo "[ax]   skip CLAUDE.md (already has @.ax/RULES.md reference)"
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────
echo ""
echo "[ax] Done! AX is installed in this project."
echo "[ax] Commit the changes and your teammates get AX automatically:"
echo ""
echo "  git add .ax .claude AGENTS.md CLAUDE.md"
echo "  git commit -m 'chore: add AX knowledge sedimentation plugin'"
