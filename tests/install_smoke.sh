#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ax-smoke.XXXXXX")"
PROJECT_ROOT="${TEST_ROOT}/project"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

assert_file() {
    test -f "$1" || {
        echo "missing file: $1" >&2
        exit 1
    }
}

assert_dir() {
    test -d "$1" || {
        echo "missing dir: $1" >&2
        exit 1
    }
}

assert_link_target() {
    local link_path="$1"
    local expected="$2"
    test -L "$link_path" || {
        echo "missing symlink: $link_path" >&2
        exit 1
    }
    local actual
    actual="$(readlink "$link_path")"
    if [ "$actual" != "$expected" ]; then
        echo "unexpected symlink target for $link_path: $actual" >&2
        exit 1
    fi
}

mkdir -p "$PROJECT_ROOT"
git -C "$PROJECT_ROOT" init -q

mkdir -p "$PROJECT_ROOT/.claude"
cat > "$PROJECT_ROOT/.claude/settings.json" <<'EOF'
{
  // keep this comment
  "note": "https://example.com//literal",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "existing",
        "hooks": [
          {
            "type": "command",
            "command": "echo keep-me"
          }
        ]
      }
    ]
  }
}
EOF

mkdir -p "$PROJECT_ROOT/.agents/skills/demo"
cat > "$PROJECT_ROOT/.agents/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: "demo"
---

# Demo
EOF

AX_SOURCE_DIR="$REPO_ROOT" bash "$REPO_ROOT/install.sh" "$PROJECT_ROOT"

assert_file "$PROJECT_ROOT/.ax/RULES.md"
assert_file "$PROJECT_ROOT/.ax/scripts/manage_claude_settings.py"
assert_file "$PROJECT_ROOT/.ax/scripts/sync_claude_skills.py"
assert_file "$PROJECT_ROOT/.git/ax-backups/settings.json"
grep -q 'keep this comment' "$PROJECT_ROOT/.git/ax-backups/settings.json"
assert_dir "$PROJECT_ROOT/docs/ai-context"
assert_file "$PROJECT_ROOT/docs/ai-context/.gitkeep"
assert_dir "$PROJECT_ROOT/.agents/skills"
assert_file "$PROJECT_ROOT/.agents/skills/.gitkeep"
assert_link_target "$PROJECT_ROOT/.claude/skills/ax" "../../.ax/skills/ax"
assert_link_target "$PROJECT_ROOT/.claude/skills/demo" "../../.agents/skills/demo"
assert_file "$PROJECT_ROOT/AGENTS.md"
assert_link_target "$PROJECT_ROOT/CLAUDE.md" "AGENTS.md"
grep -q '@.ax/RULES.md' "$PROJECT_ROOT/AGENTS.md"

python3 - "$PROJECT_ROOT/.claude/settings.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
assert data["note"] == "https://example.com//literal"
commands = [
    hook["command"]
    for entry in data["hooks"]["SessionStart"]
    for hook in entry.get("hooks", [])
]
assert "echo keep-me" in commands
ax_commands = [command for command in commands if ".ax/hooks/session-start" in command]
assert ax_commands == ["bash .ax/hooks/session-start"]
matchers = [
    entry.get("matcher")
    for entry in data["hooks"]["SessionStart"]
    if any(".ax/hooks/session-start" in hook.get("command", "") for hook in entry.get("hooks", []))
]
assert matchers == ["startup|clear|compact"]
PY

mkdir -p "$PROJECT_ROOT/.agents/skills/runtime-added"
cat > "$PROJECT_ROOT/.agents/skills/runtime-added/SKILL.md" <<'EOF'
---
name: runtime-added
description: "runtime-added"
---

# Runtime Added
EOF

python3 "$PROJECT_ROOT/.ax/scripts/sync_claude_skills.py" "$PROJECT_ROOT"
assert_link_target "$PROJECT_ROOT/.claude/skills/runtime-added" "../../.agents/skills/runtime-added"

mkdir -p "$PROJECT_ROOT/.agents/skills/stale"
ln -s ../../.agents/skills/stale "$PROJECT_ROOT/.claude/skills/stale"
python3 "$PROJECT_ROOT/.ax/scripts/sync_claude_skills.py" "$PROJECT_ROOT"
test ! -e "$PROJECT_ROOT/.claude/skills/stale"

bash "$PROJECT_ROOT/.ax/install.sh" "$PROJECT_ROOT"

python3 - "$PROJECT_ROOT/.claude/settings.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
commands = [
    hook["command"]
    for entry in data["hooks"]["SessionStart"]
    for hook in entry.get("hooks", [])
]
assert sum(1 for command in commands if ".ax/hooks/session-start" in command) == 1
PY

bash "$PROJECT_ROOT/.ax/uninstall.sh" "$PROJECT_ROOT"

test ! -e "$PROJECT_ROOT/.ax"
test ! -e "$PROJECT_ROOT/.claude/skills/ax"
test ! -e "$PROJECT_ROOT/.claude/skills/demo"
test ! -e "$PROJECT_ROOT/.claude/skills/runtime-added"
test -d "$PROJECT_ROOT/.agents/skills/demo"
test -d "$PROJECT_ROOT/.agents/skills/runtime-added"
test -L "$PROJECT_ROOT/CLAUDE.md" && {
    echo "CLAUDE.md symlink should have been removed" >&2
    exit 1
}

python3 - "$PROJECT_ROOT/.claude/settings.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
assert data["note"] == "https://example.com//literal"
commands = [
    hook["command"]
    for entry in data.get("hooks", {}).get("SessionStart", [])
    for hook in entry.get("hooks", [])
]
assert "echo keep-me" in commands
assert not any(".ax/hooks/session-start" in command for command in commands)
PY

echo "AX smoke test passed"
