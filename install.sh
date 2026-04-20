#!/usr/bin/env bash
# AX — One-line project installer
#
# Installs AX into a project so that every teammate gets it after git pull.
# Everything lives inside the project repo — no global config needed.
#
# Usage:
#   # Run from inside the target project
#   curl -fsSL https://raw.githubusercontent.com/lukelmouse-github/AgentX/main/install.sh | bash
#
#   # Or specify a project path
#   curl -fsSL https://raw.githubusercontent.com/lukelmouse-github/AgentX/main/install.sh | bash -s -- /path/to/project
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
    echo "[ax] Cloning AX into .ax/ ..."
    rm -rf "$AX_DIR"
    git clone --quiet --depth 1 https://github.com/lukelmouse-github/AgentX.git "$AX_DIR"
    rm -rf "${AX_DIR}/.git"
    echo "[ax] Embedded AX source (git history removed)"
fi

# ── 2. Set up .claude/skills/ symlinks ────────────────────────────────
SKILLS_DIR="${PROJECT_ROOT}/.claude/skills"
mkdir -p "$SKILLS_DIR"

for skill_dir in "${AX_DIR}/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    # Use relative symlink so it works on any machine
    target="${SKILLS_DIR}/${skill_name}"
    rel_path="../../.ax/skills/${skill_name}"
    if [ -L "$target" ]; then
        rm "$target"
    elif [ -e "$target" ]; then
        echo "[ax]   skip skill: ${skill_name} (exists, not a symlink)"
        continue
    fi
    ln -s "$rel_path" "$target"
    echo "[ax]   linked skill: ${skill_name}"
done

# ── 3. Configure project-level .claude/settings.json ──────────────────
SETTINGS="${PROJECT_ROOT}/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

python3 - "$SETTINGS" << 'PYEOF'
import json, sys

settings_path = sys.argv[1]

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# Commands use relative paths — works for anyone who clones the repo
start_cmd = ".ax/hooks/run-hook.cmd session-start"
end_cmd = ".ax/hooks/run-hook.cmd session-end"

def has_ax_hook(hook_list):
    return any(
        ".ax/hooks" in h.get("command", "")
        for entry in hook_list
        for h in entry.get("hooks", [])
    )

for event, cmd in [("SessionStart", start_cmd), ("Stop", end_cmd)]:
    lst = hooks.setdefault(event, [])
    if has_ax_hook(lst):
        print(f"[ax]   skip hook: {event} (already configured)")
    else:
        lst.append({"matcher": "", "hooks": [{"type": "command", "command": cmd}]})
        print(f"[ax]   added hook: {event}")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF

# ── 4. Install git post-commit hook ───────────────────────────────────
GIT_HOOKS_DIR="${PROJECT_ROOT}/.git/hooks"
POST_COMMIT="${GIT_HOOKS_DIR}/post-commit"

if [ -d "$GIT_HOOKS_DIR" ]; then
    AX_HOOK_LINE='. "$(git rev-parse --show-toplevel)/.ax/hooks/post-commit"'

    if [ -f "$POST_COMMIT" ]; then
        if grep -qF ".ax/hooks/post-commit" "$POST_COMMIT" 2>/dev/null; then
            echo "[ax]   skip git hook: post-commit (already configured)"
        else
            # Append to existing post-commit hook
            echo "" >> "$POST_COMMIT"
            echo "# AX post-commit hook" >> "$POST_COMMIT"
            echo "$AX_HOOK_LINE" >> "$POST_COMMIT"
            chmod +x "$POST_COMMIT"
            echo "[ax]   appended to git hook: post-commit"
        fi
    else
        # Create new post-commit hook
        cat > "$POST_COMMIT" << 'HOOKEOF'
#!/usr/bin/env bash
HOOKEOF
        echo "$AX_HOOK_LINE" >> "$POST_COMMIT"
        chmod +x "$POST_COMMIT"
        echo "[ax]   created git hook: post-commit"
    fi
fi

# ── 5. Create .ax.json ────────────────────────────────────────────────
AX_CONF="${PROJECT_ROOT}/.ax.json"
if [ ! -f "$AX_CONF" ]; then
    echo '{"enabled": true}' > "$AX_CONF"
    echo "[ax]   created .ax.json"
fi

# ── Done ──────────────────────────────────────────────────────────────
echo ""
echo "[ax] Done! AX is installed in this project."
echo "[ax] Commit the changes and your teammates get AX automatically:"
echo ""
echo "  git add .ax .ax.json .claude"
echo "  git commit -m 'chore: add AX knowledge sedimentation plugin'"
