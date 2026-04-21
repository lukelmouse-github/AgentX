---
name: ax
description: "Project knowledge sedimentation — extract valuable knowledge from AI coding sessions into Markdown docs and project skills, then share them through git."
---

# AX — Project Knowledge Sedimentation

Extract valuable knowledge from AI coding sessions and save it in repo-native paths.

## Usage

```text
/ax
/ax <prompt>
/ax architecture
/ax skill <name>
```

## Workflow

Follow these steps in order.

### Step 0: Pick Exactly One History Adapter

Use the adapter that matches the **current agent**. Do not read another agent's local history in the same `/ax` run.

| Agent | Adapter |
|------|---------|
| Claude Code | Current conversation + recent git changes + local Claude Code session history under `~/.claude/projects` |
| Codex | Current conversation + recent git changes + files read or written in this session |

**For Codex:** do not guess private transcript paths under `~/.codex`, `~/.config`, or similar locations. If the current conversation plus git evidence is insufficient, ask the user for direction instead of scraping local history.

### Step 1: Collect Data

**1a. Current session context**

Gather from the current conversation:

- files read or written
- bugs found
- root causes identified
- solutions applied
- key design decisions

**1b. Recent git changes**

```bash
git log --oneline -10
git diff --stat
```

**1c. Claude Code adapter only: local session history**

If the current agent is Claude Code, do a two-level scan of recent local session history.

**Level 1: quick scan**

```bash
PROJECT_DIR=$(pwd)
SESSION_BASE="${HOME}/.claude/projects"
PROJECT_HASH=$(echo -n "${PROJECT_DIR}" | sed 's|/|-|g' | sed 's|^-||')
SESSION_DIR="${SESSION_BASE}/${PROJECT_HASH}"

if [ ! -d "$SESSION_DIR" ]; then
  SESSION_DIR=$(ls -d ${SESSION_BASE}/*${PROJECT_DIR##*/}* 2>/dev/null | head -1)
fi

if [ -d "$SESSION_DIR" ]; then
  find "$SESSION_DIR" -name "*.jsonl" -mtime -7 -type f | xargs ls -t 2>/dev/null | head -10
fi
```

For each candidate session file, extract only the first 10 user messages:

```bash
python3 -c "
import json, sys
count = 0
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        if d.get('type') != 'user':
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
            print(text[:200])
            count += 1
            if count >= 10:
                sys.exit()
" <session_file>
```

Write a one-line summary for each session and decide which 1-3 sessions are worth deeper extraction.

**Level 2: deep extract**

For each selected session, extract only user and assistant text:

```bash
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
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
            if len(text) > 500:
                text = text[:500] + '...[truncated]'
            print(f'[{msg_type}] {text}')
" <session_file>
```

Ignore tool calls, tool results, file snapshots, and other noise.

### Step 2: Analyze and Extract

Identify knowledge worth saving.

| Type | Target Path | When |
|------|-------------|------|
| Architecture knowledge | `docs/ai-context/{topic}.md` | Core design, data flow, system principles |
| Project skill | `.agents/skills/{name}/SKILL.md` | Repeatable workflows such as debugging, deployment, review |
| Module documentation | `{module}/AGENTS.md` | Module-specific context, APIs, gotchas |

Rules:

- If the user provided a prompt, focus extraction around that topic.
- Reuse or update existing files when the content overlaps.
- Keep each written file under 200 lines.

### Step 3: Preview and Confirm

For each file you want to write, show the user:

1. target path
2. content preview
3. why this knowledge is worth saving

Then ask for explicit confirmation in the conversation. Do not rely on tool-specific UI helpers. **Do not write any file without explicit user confirmation.**

### Step 4: Validate

Run these checks before writing.

**4a. Line count gate**

```bash
echo "<draft content>" | wc -l
```

If the draft exceeds 200 lines, split it and use `@` references.

**4b. Duplication scan**

```bash
grep -rl "<2-3 core keywords from draft>" docs/ai-context/ .agents/skills/ 2>/dev/null || echo "no duplicates"
```

If an overlapping file exists, update it instead of creating a duplicate.

**4c. `@` reference validity**

```bash
for ref in $(python3 -c "
import re, sys
draft = sys.stdin.read()
for ref in re.findall(r'@([\\w/.,-]+\\.\\w+)', draft):
    print(ref)
" <<'EOF'
<draft content>
EOF
); do
  test -f "$ref" || echo "BROKEN: $ref"
done
```

Fix any broken reference before writing.

**4d. Actionable content**

Reject vague advice. Saved knowledge must include concrete commands, paths, patterns, or steps.

### Step 5: Write Files

For confirmed files:

1. Write the file content.
2. Update the nearest parent `AGENTS.md` with an `@` reference when needed.
3. If the write created or updated `.agents/skills/{name}/SKILL.md`, sync Claude Code adapters:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if [ -f "$PROJECT_ROOT/.ax/scripts/sync_claude_skills.py" ]; then
  python3 "$PROJECT_ROOT/.ax/scripts/sync_claude_skills.py" "$PROJECT_ROOT"
fi
```

4. If `AGENTS.md` does not exist at the project root, create it with an `@.ax/RULES.md` reference.
5. If `CLAUDE.md` does not exist, create it as a symlink or pointer to `AGENTS.md`.

### Step 6: Summary

Report:

- files written or updated
- files skipped
- any follow-up review the user should do before committing

Never auto-commit.

## Output Conventions

### File Constraints

- Each markdown file must stay under 200 lines.
- Use `@` references to link related docs.
- Follow the existing AGENTS hierarchy when it exists.

### Supported Agents

| Tool | Knowledge Entry | Skill Consumption |
|------|-----------------|------------------|
| Claude Code | `CLAUDE.md` + SessionStart hook | `.claude/skills/` symlinks to `.ax/skills/ax` and `.agents/skills/*` |
| Codex | `AGENTS.md` | `.agents/skills/` |

### AGENTS.md Template

```markdown
# {Project Name}

## Instructions

### AGENTS.md 读取规则
修改或设计涉及某目录的代码前，必须先读该目录及父目录的 AGENTS.md。

### 知识沉淀
项目知识只写入 `.agents/skills/`、`docs/ai-context/` 和模块 `AGENTS.md`。
所有沉淀与知识修订都必须通过 `/ax` 流程完成，详见 @.ax/RULES.md。

## Quick Start
Key commands and setup.

## Architecture
High-level architecture summary.

## Module Index
- @{module}/AGENTS.md — Module description

## Deep Dive Docs
- @docs/ai-context/{topic}.md — Topic description
```

## Key Principles

- Human in the loop: every write requires explicit confirmation.
- Repo-native knowledge: project docs and project skills live outside `.ax/`.
- One adapter per run: only read the history source that matches the current agent.
