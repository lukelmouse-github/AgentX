#!/usr/bin/env bash
# AX — Project installer
#
# Embeds AX into a git repository so knowledge lives in the project and is
# shared through normal git workflows.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/lukelmouse-github/AgentX/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/lukelmouse-github/AgentX/main/install.sh | bash -s -- /path/to/project
#   AX_SOURCE_DIR=/path/to/local/ax bash install.sh /path/to/project
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
DEFAULT_AX_REPO_URL="https://github.com/lukelmouse-github/AgentX.git"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ax-install.XXXXXX")"
if [ "${#BASH_SOURCE[@]}" -gt 0 ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR=""
fi
STAGED_SOURCE="${WORK_DIR}/source"
PAYLOAD_DIR="${WORK_DIR}/payload"
SOURCE_DIR="${AX_SOURCE_DIR:-}"
PAYLOAD_ITEMS=(
    "RULES.md"
    "README.md"
    "hooks"
    "skills"
    "scripts"
    "install.sh"
    "uninstall.sh"
)

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [ -z "$SOURCE_DIR" ] && [ -f "${SCRIPT_DIR}/RULES.md" ] && [ -d "${SCRIPT_DIR}/skills" ]; then
    SOURCE_DIR="$SCRIPT_DIR"
fi

if [ -n "$SOURCE_DIR" ]; then
    SOURCE_DIR="$(cd "$SOURCE_DIR" 2>/dev/null && pwd)" || {
        echo "[ax] Error: AX_SOURCE_DIR not found: ${AX_SOURCE_DIR}"
        exit 1
    }
    echo "[ax] Using AX source from: ${SOURCE_DIR}"
else
    AX_REPO_URL="${AX_REPO_URL:-$DEFAULT_AX_REPO_URL}"
    SOURCE_DIR="${STAGED_SOURCE}"
    echo "[ax] Fetching AX source from: ${AX_REPO_URL}"
    git clone --quiet --depth 1 "$AX_REPO_URL" "$SOURCE_DIR"
fi

mkdir -p "$PAYLOAD_DIR"
for item in "${PAYLOAD_ITEMS[@]}"; do
    if [ ! -e "${SOURCE_DIR}/${item}" ]; then
        echo "[ax] Error: AX source is missing ${item}"
        exit 1
    fi
    cp -R "${SOURCE_DIR}/${item}" "${PAYLOAD_DIR}/${item}"
done

if [ -d "$AX_DIR" ]; then
    BACKUP="${AX_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    cp -R "$AX_DIR" "$BACKUP"
    echo "[ax] Backed up existing .ax/ to $(basename "$BACKUP")/"
    rm -rf "$AX_DIR"
fi

mkdir -p "$AX_DIR"
for item in "${PAYLOAD_ITEMS[@]}"; do
    cp -R "${PAYLOAD_DIR}/${item}" "${AX_DIR}/${item}"
done
chmod +x "${AX_DIR}/install.sh" "${AX_DIR}/uninstall.sh" "${AX_DIR}/hooks/session-start"
find "${AX_DIR}/scripts" -type f -name "*.py" -exec chmod +x {} +
echo "[ax] Embedded AX payload into .ax/"

# ── 2. Create canonical project knowledge directories ─────────────────
mkdir -p "${PROJECT_ROOT}/.agents/skills"
touch "${PROJECT_ROOT}/.agents/skills/.gitkeep"

DOCS_DIR="${PROJECT_ROOT}/docs/ai-context"
mkdir -p "$DOCS_DIR"
touch "${DOCS_DIR}/.gitkeep"

# ── 3. Add Claude Code adapters (hook + skill symlinks) ──────────────
mkdir -p "${PROJECT_ROOT}/.claude"
SETTINGS="${PROJECT_ROOT}/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
python3 "${AX_DIR}/scripts/manage_claude_settings.py" add "$SETTINGS" "bash .ax/hooks/session-start"
python3 "${AX_DIR}/scripts/sync_claude_skills.py" "$PROJECT_ROOT"

# ── 4. Create AGENTS.md + CLAUDE.md if missing ───────────────────────
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

项目知识只写入 .agents/skills/、docs/ai-context/ 和模块 AGENTS.md。
所有沉淀与知识修订都必须通过 /ax 流程完成，详见 @.ax/RULES.md。

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
elif ! grep -q '@\.ax/RULES\.md' "$AGENTS_MD" 2>/dev/null; then
    cat >> "$AGENTS_MD" << 'APPENDEOF'

### 知识沉淀

项目知识只写入 .agents/skills/、docs/ai-context/ 和模块 AGENTS.md。
所有沉淀与知识修订都必须通过 /ax 流程完成，详见 @.ax/RULES.md。
APPENDEOF
    echo "[ax]   appended sedimentation rules to existing AGENTS.md"
else
    echo "[ax]   skip AGENTS.md (already has @.ax/RULES.md reference)"
fi

CLAUDE_MD="${PROJECT_ROOT}/CLAUDE.md"
if [ ! -f "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ]; then
    ln -s AGENTS.md "$CLAUDE_MD"
    echo "[ax]   created CLAUDE.md → AGENTS.md symlink"
elif [ -f "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ] && ! grep -q '@\.ax/RULES\.md' "$CLAUDE_MD" 2>/dev/null; then
    cat >> "$CLAUDE_MD" << 'APPENDEOF'

### 知识沉淀

项目知识只写入 .agents/skills/、docs/ai-context/ 和模块 AGENTS.md。
所有沉淀与知识修订都必须通过 /ax 流程完成，详见 @.ax/RULES.md。
APPENDEOF
    echo "[ax]   appended sedimentation rules to existing CLAUDE.md"
else
    echo "[ax]   skip CLAUDE.md (already has @.ax/RULES.md reference or is managed separately)"
fi

echo ""
echo "[ax] Done! AX is installed in this project."
echo "[ax] Commit the changes so teammates get the same knowledge stack:"
echo ""
echo "  git add .ax .agents .claude AGENTS.md CLAUDE.md docs/ai-context"
echo "  git commit -m 'chore: add AX knowledge sedimentation'"
