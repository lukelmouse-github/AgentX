#!/usr/bin/env bash
# AX plugin smoke test — validates plugin structure, hook scripts, and skill content

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0

assert() {
    local desc="$1"
    shift
    if "$@" 2>/dev/null; then
        echo "  ok: $desc"
        pass=$((pass + 1))
    else
        echo "  FAIL: $desc"
        fail=$((fail + 1))
    fi
}

# ── 1. Plugin structure ────────────────────────────────────────────
echo "=== Plugin structure ==="

assert "plugin.json exists" test -f "$REPO_ROOT/.claude-plugin/plugin.json"
assert "marketplace.json exists" test -f "$REPO_ROOT/.claude-plugin/marketplace.json"
assert "hooks.json exists" test -f "$REPO_ROOT/hooks/hooks.json"
assert "post-tool-use.sh exists and is executable" test -x "$REPO_ROOT/scripts/post-tool-use.sh"
assert "ax-review.sh exists and is executable" test -x "$REPO_ROOT/scripts/ax-review.sh"
assert "ax SKILL.md exists" test -f "$REPO_ROOT/skills/ax/SKILL.md"
assert "RULES.md exists" test -f "$REPO_ROOT/RULES.md"

# ── 2. Deleted files must not exist ────────────────────────────────
echo "=== Deleted files must not exist ==="

assert "eval_profile.py removed" test ! -f "$REPO_ROOT/scripts/eval_profile.py"
assert "stop-check.sh removed" test ! -f "$REPO_ROOT/scripts/stop-check.sh"
assert "session-start.sh removed" test ! -f "$REPO_ROOT/scripts/session-start.sh"
assert "user-prompt-submit.sh removed" test ! -f "$REPO_ROOT/scripts/user-prompt-submit.sh"
assert "skills/init/ removed" test ! -d "$REPO_ROOT/skills/init"
assert "install.sh removed" test ! -f "$REPO_ROOT/install.sh"
assert "uninstall.sh removed" test ! -f "$REPO_ROOT/uninstall.sh"
assert "manage_claude_settings.py removed" test ! -f "$REPO_ROOT/scripts/manage_claude_settings.py"
assert "sync_claude_skills.py removed" test ! -f "$REPO_ROOT/scripts/sync_claude_skills.py"
assert "hooks/session-start removed" test ! -f "$REPO_ROOT/hooks/session-start"
assert "hooks/stop-check removed" test ! -f "$REPO_ROOT/hooks/stop-check"
assert "eval-sedimentation-default.sh removed" test ! -f "$REPO_ROOT/scripts/eval-sedimentation-default.sh"

# ── 3. Script syntax checks ───────────────────────────────────────
echo "=== Script syntax checks ==="

assert "post-tool-use.sh syntax ok" bash -n "$REPO_ROOT/scripts/post-tool-use.sh"
assert "ax-review.sh syntax ok" bash -n "$REPO_ROOT/scripts/ax-review.sh"

# ── 4. plugin.json validity ───────────────────────────────────────
echo "=== plugin.json ==="

PLUGIN_NAME=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['name'])")
assert "plugin name is 'ax'" test "$PLUGIN_NAME" = "ax"

# ── 5. hooks.json validation ──────────────────────────────────────
echo "=== hooks.json ==="

assert "hooks.json is valid JSON" jq . "$REPO_ROOT/hooks/hooks.json"
assert "hooks.json contains PostToolUse" grep -q 'PostToolUse' "$REPO_ROOT/hooks/hooks.json"
assert "hooks.json does NOT contain SessionStart" test -z "$(grep 'SessionStart' "$REPO_ROOT/hooks/hooks.json")"
assert "hooks.json does NOT contain Stop" test -z "$(grep '"Stop"' "$REPO_ROOT/hooks/hooks.json")"
assert "hooks.json does NOT contain UserPromptSubmit" test -z "$(grep 'UserPromptSubmit' "$REPO_ROOT/hooks/hooks.json")"

# Verify PostToolUse is async
python3 - "$REPO_ROOT" <<'PY'
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
data = json.loads((root / "hooks" / "hooks.json").read_text())
ptu = data["hooks"]["PostToolUse"][0]["hooks"][0]
assert ptu.get("async") is True, "PostToolUse hook must be async"
PY
assert "PostToolUse hook is async" test $? -eq 0

# Verify hooks.json scripts all exist
python3 - "$REPO_ROOT" <<'PY'
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
data = json.loads((root / "hooks" / "hooks.json").read_text())
hooks = data["hooks"]

for event, entries in hooks.items():
    for entry in entries:
        for hook in entry.get("hooks", []):
            cmd = hook["command"]
            script = cmd.replace("bash ${CLAUDE_PLUGIN_ROOT}/", "")
            assert (root / script).is_file(), f"missing script: {script}"
PY
assert "hooks.json scripts all exist" test $? -eq 0

# ── 6. Skill content checks ───────────────────────────────────────
echo "=== Skill content ==="

assert "ax SKILL.md mentions AGENTS.md" grep -q 'AGENTS.md' "$REPO_ROOT/skills/ax/SKILL.md"
assert "RULES.md mentions /ax:ax" grep -q '/ax:ax' "$REPO_ROOT/RULES.md"
assert "RULES.md mentions cross-agent" grep -q '跨 Agent' "$REPO_ROOT/RULES.md"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Results: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
    exit 1
fi
