#!/usr/bin/env bash
# AX plugin smoke test — validates plugin structure, hook scripts, eval_profile engine, and stop-check dispatcher

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ax-smoke.XXXXXX")"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

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
assert "hooks.json exists" test -f "$REPO_ROOT/hooks/hooks.json"
assert "session-start.sh exists" test -x "$REPO_ROOT/scripts/session-start.sh"
assert "stop-check.sh exists" test -x "$REPO_ROOT/scripts/stop-check.sh"
assert "post-tool-use.sh exists" test -x "$REPO_ROOT/scripts/post-tool-use.sh"
assert "user-prompt-submit.sh exists" test -x "$REPO_ROOT/scripts/user-prompt-submit.sh"
assert "eval_profile.py exists" test -f "$REPO_ROOT/scripts/eval_profile.py"
assert "ax SKILL.md exists" test -f "$REPO_ROOT/skills/ax/SKILL.md"
assert "init SKILL.md exists" test -f "$REPO_ROOT/skills/init/SKILL.md"
assert "RULES.md exists" test -f "$REPO_ROOT/RULES.md"

# ── 2. plugin.json validity ────────────────────────────────────────
echo "=== plugin.json ==="

PLUGIN_NAME=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['name'])")
assert "plugin name is 'ax'" test "$PLUGIN_NAME" = "ax"

# ── 3. hooks.json references valid scripts ──────────────────────────
echo "=== hooks.json ==="

python3 - "$REPO_ROOT" <<'PY'
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
data = json.loads((root / "hooks" / "hooks.json").read_text())
hooks = data["hooks"]

assert "SessionStart" in hooks, "missing SessionStart"
assert "PostToolUse" in hooks, "missing PostToolUse"
assert "UserPromptSubmit" in hooks, "missing UserPromptSubmit"
assert "Stop" in hooks, "missing Stop"

for event, entries in hooks.items():
    for entry in entries:
        for hook in entry.get("hooks", []):
            cmd = hook["command"]
            script = cmd.replace("bash ${CLAUDE_PLUGIN_ROOT}/", "")
            assert (root / script).is_file(), f"missing script: {script}"
PY
assert "hooks.json scripts all exist" test $? -eq 0

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

# ── 4. session-start.sh outputs valid JSON ──────────────────────────
echo "=== session-start.sh ==="

SESSION_OUT=$(echo '{}' | bash "$REPO_ROOT/scripts/session-start.sh")
echo "$SESSION_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'additionalContext' in d"
assert "session-start outputs valid JSON with additionalContext" test $? -eq 0

# ── 5. post-tool-use.sh signal accumulation ─────────────────────────
echo "=== post-tool-use.sh ==="

FAKE_SESSION="ax-smoke-test-$$"
SIGNAL_FILE="/tmp/ax-signals-${FAKE_SESSION}.jsonl"
rm -f "$SIGNAL_FILE"

# Send a Write tool signal
printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"src/core/main.py","command":""}}' "$FAKE_SESSION" \
    | bash "$REPO_ROOT/scripts/post-tool-use.sh"
assert "signal file created" test -f "$SIGNAL_FILE"

# Send a Bash tool signal
printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"file_path":"","command":"pytest tests/"}}' "$FAKE_SESSION" \
    | bash "$REPO_ROOT/scripts/post-tool-use.sh"

SIGNAL_LINES=$(wc -l < "$SIGNAL_FILE" | tr -d ' ')
assert "signal file has 2 lines" test "$SIGNAL_LINES" = "2"

# Verify signal JSON structure
python3 -c "
import json
with open('$SIGNAL_FILE') as f:
    lines = [json.loads(l) for l in f]
assert lines[0]['tool'] == 'Write', f'expected Write, got {lines[0][\"tool\"]}'
assert lines[0]['path'] == 'src/core/main.py'
assert lines[1]['tool'] == 'Bash'
assert lines[1]['cmd'] == 'pytest tests/'
"
assert "signal JSON structure is correct" test $? -eq 0

# Empty session_id → no signal file created
EMPTY_SIGNAL="/tmp/ax-signals-.jsonl"
rm -f "$EMPTY_SIGNAL"
printf '{"tool_name":"Read","tool_input":{"file_path":"foo.py"}}' \
    | bash "$REPO_ROOT/scripts/post-tool-use.sh"
assert "empty session_id produces no signal file" test ! -f "$EMPTY_SIGNAL"

rm -f "$SIGNAL_FILE"

# ── 6. eval_profile.py ──────────────────────────────────────────────
echo "=== eval_profile.py ==="

# 6a. No signals, no profile → false
RESULT_EMPTY=$(python3 "$REPO_ROOT/scripts/eval_profile.py" "/nonexistent" "/nonexistent" "/nonexistent")
assert "no signals returns false" test "$RESULT_EMPTY" = "false"

# 6b. Default profile, enough signals → true (50 tools + 5 writes)
SIGNALS_BUSY="$TEST_ROOT/signals_busy.jsonl"
for i in $(seq 1 45); do
    echo '{"tool":"Read","path":"foo.py","cmd":""}' >> "$SIGNALS_BUSY"
done
for i in $(seq 1 5); do
    echo '{"tool":"Write","path":"src/file${i}.py","cmd":""}' >> "$SIGNALS_BUSY"
done

RESULT_BUSY=$(python3 "$REPO_ROOT/scripts/eval_profile.py" "/nonexistent" "$SIGNALS_BUSY" "/nonexistent")
assert "default profile, 50 tools + 5 writes returns true" test "$RESULT_BUSY" = "true"

# 6c. Default profile, not enough signals → false (below all thresholds)
SIGNALS_QUIET="$TEST_ROOT/signals_quiet.jsonl"
for i in $(seq 1 10); do
    echo '{"tool":"Read","path":"foo.py","cmd":""}' >> "$SIGNALS_QUIET"
done
echo '{"tool":"Write","path":"src/main.py","cmd":""}' >> "$SIGNALS_QUIET"

RESULT_QUIET=$(python3 "$REPO_ROOT/scripts/eval_profile.py" "/nonexistent" "$SIGNALS_QUIET" "/nonexistent")
assert "default profile, 11 tools + 1 write returns false" test "$RESULT_QUIET" = "false"

# 6d. Custom profile with key_paths
PROFILE_CUSTOM="$TEST_ROOT/profile.yaml"
cat > "$PROFILE_CUSTOM" <<'YAML'
project:
  name: test-project
  type: web-api

signals:
  key_paths:
    - src/api/
    - src/core/
  test_patterns:
    - pytest

triggers:
  - when: "key_path_edits >= 1 and tool_count >= 3"
    reason: "modified key paths"
  - when: "test_runs >= 1"
    reason: "ran tests"
YAML

SIGNALS_KEY="$TEST_ROOT/signals_key.jsonl"
echo '{"tool":"Read","path":"README.md","cmd":""}' >> "$SIGNALS_KEY"
echo '{"tool":"Write","path":"src/api/routes.py","cmd":""}' >> "$SIGNALS_KEY"
echo '{"tool":"Edit","path":"src/core/models.py","cmd":""}' >> "$SIGNALS_KEY"

RESULT_KEY=$(python3 "$REPO_ROOT/scripts/eval_profile.py" "$PROFILE_CUSTOM" "$SIGNALS_KEY" "/nonexistent")
assert "custom profile, key_path_edits trigger fires" test "$RESULT_KEY" = "true"

# 6e. Custom profile, test_patterns trigger
SIGNALS_TEST="$TEST_ROOT/signals_test.jsonl"
echo '{"tool":"Bash","path":"","cmd":"pytest tests/ -v"}' >> "$SIGNALS_TEST"

RESULT_TEST=$(python3 "$REPO_ROOT/scripts/eval_profile.py" "$PROFILE_CUSTOM" "$SIGNALS_TEST" "/nonexistent")
assert "custom profile, test_runs trigger fires" test "$RESULT_TEST" = "true"

# 6f. Custom profile, no trigger match
SIGNALS_MISS="$TEST_ROOT/signals_miss.jsonl"
echo '{"tool":"Read","path":"docs/readme.md","cmd":""}' >> "$SIGNALS_MISS"
echo '{"tool":"Read","path":"docs/guide.md","cmd":""}' >> "$SIGNALS_MISS"

RESULT_MISS=$(python3 "$REPO_ROOT/scripts/eval_profile.py" "$PROFILE_CUSTOM" "$SIGNALS_MISS" "/nonexistent")
assert "custom profile, no trigger match returns false" test "$RESULT_MISS" = "false"

# 6g. Transcript fallback (no signal file, uses transcript)
TRANSCRIPT_FB="$TEST_ROOT/transcript_fb.jsonl"
for i in $(seq 1 45); do
    echo '{"type":"tool_use","name":"Read"}' >> "$TRANSCRIPT_FB"
done
for i in $(seq 1 5); do
    echo '{"type":"tool_use","name":"Write"}' >> "$TRANSCRIPT_FB"
done

RESULT_FB=$(python3 "$REPO_ROOT/scripts/eval_profile.py" "/nonexistent" "/nonexistent" "$TRANSCRIPT_FB")
assert "transcript fallback with default profile triggers" test "$RESULT_FB" = "true"

# ── 7. stop-check.sh dispatcher ─────────────────────────────────────
echo "=== stop-check.sh dispatcher ==="

PROJECT_DIR="$TEST_ROOT/project"
mkdir -p "$PROJECT_DIR/.ax"
git -C "$PROJECT_DIR" init -q

# Create a transcript with enough tool calls for default triggers (50+ tools, 5+ writes)
TRANSCRIPT="$TEST_ROOT/transcript.jsonl"
for i in $(seq 1 45); do
    echo '{"type":"tool_use","name":"Read"}' >> "$TRANSCRIPT"
done
for i in $(seq 1 5); do
    echo '{"type":"tool_use","name":"Write"}' >> "$TRANSCRIPT"
done

# 7a. Without profile → uses default → should block (via transcript fallback)
STOP_OUT=$(printf '{"stop_hook_active":false,"session_id":"test-stop","transcript_path":"%s"}' "$TRANSCRIPT" \
    | (cd "$PROJECT_DIR" && bash "$REPO_ROOT/scripts/stop-check.sh"))
echo "$STOP_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['decision']=='block'" 2>/dev/null
assert "stop-check blocks on busy transcript (no profile)" test $? -eq 0

# 7b. With profile that won't match → should pass
cat > "$PROJECT_DIR/.ax/profile.yaml" <<'YAML'
signals:
  key_paths:
    - nonexistent/path/
  test_patterns: []
triggers:
  - when: "key_path_edits >= 100"
    reason: "unreachable"
YAML

STOP_OUT2=$(printf '{"stop_hook_active":false,"session_id":"test-stop","transcript_path":"%s"}' "$TRANSCRIPT" \
    | (cd "$PROJECT_DIR" && bash "$REPO_ROOT/scripts/stop-check.sh"))
assert "stop-check passes when profile triggers don't match" test -z "$STOP_OUT2"

# 7c. With profile that matches → should block
cat > "$PROJECT_DIR/.ax/profile.yaml" <<'YAML'
signals:
  key_paths: []
  test_patterns: []
triggers:
  - when: "tool_count >= 1"
    reason: "always trigger"
YAML

STOP_OUT3=$(printf '{"stop_hook_active":false,"session_id":"test-stop","transcript_path":"%s"}' "$TRANSCRIPT" \
    | (cd "$PROJECT_DIR" && bash "$REPO_ROOT/scripts/stop-check.sh"))
echo "$STOP_OUT3" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['decision']=='block'" 2>/dev/null
assert "stop-check blocks when profile triggers match" test $? -eq 0

# 7d. stop_hook_active guard
STOP_OUT4=$(printf '{"stop_hook_active":true,"session_id":"test-stop","transcript_path":"%s"}' "$TRANSCRIPT" \
    | (cd "$PROJECT_DIR" && bash "$REPO_ROOT/scripts/stop-check.sh"))
assert "stop-check passes when stop_hook_active=true" test -z "$STOP_OUT4"

# 7e. /ax already called → skip
AX_TRANSCRIPT="$TEST_ROOT/ax_transcript.jsonl"
for i in $(seq 1 45); do
    echo '{"type":"tool_use","name":"Read"}' >> "$AX_TRANSCRIPT"
done
for i in $(seq 1 5); do
    echo '{"type":"tool_use","name":"Write"}' >> "$AX_TRANSCRIPT"
done
echo '{"type":"user","message":{"content":"/ax"}}' >> "$AX_TRANSCRIPT"

STOP_OUT5=$(printf '{"stop_hook_active":false,"session_id":"test-stop","transcript_path":"%s"}' "$AX_TRANSCRIPT" \
    | (cd "$PROJECT_DIR" && bash "$REPO_ROOT/scripts/stop-check.sh"))
assert "stop-check passes when /ax already called" test -z "$STOP_OUT5"

# 7f. stop-check writes pending marker
PENDING_CHECK="/tmp/ax-pending-test-stop"
rm -f "$PENDING_CHECK"
cat > "$PROJECT_DIR/.ax/profile.yaml" <<'YAML'
signals:
  key_paths: []
  test_patterns: []
triggers:
  - when: "tool_count >= 1"
    reason: "always trigger"
YAML

printf '{"stop_hook_active":false,"session_id":"test-stop","transcript_path":"%s"}' "$TRANSCRIPT" \
    | (cd "$PROJECT_DIR" && bash "$REPO_ROOT/scripts/stop-check.sh") > /dev/null
assert "stop-check writes pending marker file" test -f "$PENDING_CHECK"
rm -f "$PENDING_CHECK"

# 7g. stop-check reason contains auto-execute instruction
STOP_OUT6=$(printf '{"stop_hook_active":false,"session_id":"test-stop-reason","transcript_path":"%s"}' "$TRANSCRIPT" \
    | (cd "$PROJECT_DIR" && bash "$REPO_ROOT/scripts/stop-check.sh"))
echo "$STOP_OUT6" | grep -q '立即执行'
assert "stop-check reason instructs auto-execution" test $? -eq 0
rm -f "/tmp/ax-pending-test-stop-reason"

# ── 8. user-prompt-submit.sh ────────────────────────────────────────
echo "=== user-prompt-submit.sh ==="

# 8a. No pending file → no output
UPS_OUT1=$(printf '{"session_id":"ups-test-1","prompt":"hello"}' \
    | bash "$REPO_ROOT/scripts/user-prompt-submit.sh")
assert "no pending file → no output" test -z "$UPS_OUT1"

# 8b. Pending file + user says /ax → accepted, pending deleted
echo '{"tool_count":8}' > "/tmp/ax-pending-ups-test-2"
UPS_OUT2=$(printf '{"session_id":"ups-test-2","prompt":"/ax:ax"}' \
    | bash "$REPO_ROOT/scripts/user-prompt-submit.sh")
assert "accept: /ax prompt → no output" test -z "$UPS_OUT2"
assert "accept: pending file deleted" test ! -f "/tmp/ax-pending-ups-test-2"

# 8c. Pending file + user doesn't say /ax → rejected, reflection injected
echo '{"tool_count":8}' > "/tmp/ax-pending-ups-test-3"
UPS_OUT3=$(printf '{"session_id":"ups-test-3","prompt":"继续上面的工作"}' \
    | bash "$REPO_ROOT/scripts/user-prompt-submit.sh")
echo "$UPS_OUT3" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'additionalContext' in d.get('hookSpecificOutput', {})" 2>/dev/null
assert "reject: outputs additionalContext with reflection" test $? -eq 0
echo "$UPS_OUT3" | grep -q 'AX 反思'
assert "reject: reflection mentions AX 反思" test $? -eq 0
assert "reject: pending file deleted" test ! -f "/tmp/ax-pending-ups-test-3"

# 8d. Empty session_id → no output
echo '{"tool_count":8}' > "/tmp/ax-pending-.jsonl"
UPS_OUT4=$(printf '{"prompt":"hello"}' \
    | bash "$REPO_ROOT/scripts/user-prompt-submit.sh")
assert "empty session_id → no output" test -z "$UPS_OUT4"
rm -f "/tmp/ax-pending-.jsonl"

# ── 9. Skill content checks ─────────────────────────────────────────
echo "=== Skill content ==="

assert "ax SKILL.md mentions /ax:init" grep -q '/ax:init' "$REPO_ROOT/skills/ax/SKILL.md"
assert "ax SKILL.md mentions cross-agent" grep -q 'AGENTS.md' "$REPO_ROOT/skills/ax/SKILL.md"
assert "init SKILL.md is in Chinese" grep -q '何时使用' "$REPO_ROOT/skills/init/SKILL.md"
assert "init SKILL.md mentions profile.yaml" grep -q 'profile.yaml' "$REPO_ROOT/skills/init/SKILL.md"
assert "init SKILL.md mentions when expressions" grep -q 'when:' "$REPO_ROOT/skills/init/SKILL.md"
assert "RULES.md mentions /ax:ax" grep -q '/ax:ax' "$REPO_ROOT/RULES.md"
assert "RULES.md mentions cross-agent" grep -q '跨 Agent' "$REPO_ROOT/RULES.md"

# ── 10. Old files removed ───────────────────────────────────────────
echo "=== Cleanup verification ==="

assert "install.sh removed" test ! -f "$REPO_ROOT/install.sh"
assert "uninstall.sh removed" test ! -f "$REPO_ROOT/uninstall.sh"
assert "manage_claude_settings.py removed" test ! -f "$REPO_ROOT/scripts/manage_claude_settings.py"
assert "sync_claude_skills.py removed" test ! -f "$REPO_ROOT/scripts/sync_claude_skills.py"
assert "hooks/session-start removed" test ! -f "$REPO_ROOT/hooks/session-start"
assert "hooks/stop-check removed" test ! -f "$REPO_ROOT/hooks/stop-check"
assert "eval-sedimentation-default.sh removed" test ! -f "$REPO_ROOT/scripts/eval-sedimentation-default.sh"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Results: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
    exit 1
fi
