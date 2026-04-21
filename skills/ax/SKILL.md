---
name: ax
description: "Project knowledge sedimentation — extract valuable knowledge from sessions into Markdown docs and Skills, shared via git. Use /ax [prompt] to analyze and save knowledge."
---

# AX — Project Knowledge Sedimentation

Extract valuable knowledge from AI coding sessions and save it as structured docs and skills.

## Usage

```
/ax                          # Full scan, recommend what to save
/ax <prompt>                 # Extract around a specific topic (supports Chinese/English)
/ax architecture             # Update architecture docs only
/ax skill <name>             # Create/update a specific skill
```

## Workflow

Follow these steps strictly in order:

### Step 1: Collect Data

**1a. Current session context**

Gather from the current conversation: files read/written, decisions made, bugs found, solutions applied.

**1b. Recent git changes**

```bash
git log --oneline -10
git diff --stat
```

**1c. Recent local session history (last 7 days, two-level scan)**

Read recent Claude Code session logs from the local machine — this data is NOT committed to git.

**Level 1: Quick scan — one-line summary per session**

```bash
# Find the project session directory
PROJECT_DIR=$(pwd)
SESSION_BASE="${HOME}/.claude/projects"
PROJECT_HASH=$(echo -n "${PROJECT_DIR}" | sed 's|/|-|g' | sed 's|^-||')
SESSION_DIR="${SESSION_BASE}/${PROJECT_HASH}"

if [ ! -d "$SESSION_DIR" ]; then
  SESSION_DIR=$(ls -d ${SESSION_BASE}/*${PROJECT_DIR##*/}* 2>/dev/null | head -1)
fi

# List .jsonl files modified in last 7 days, newest first, max 10
if [ -d "$SESSION_DIR" ]; then
  find "$SESSION_DIR" -name "*.jsonl" -mtime -7 -type f | xargs ls -t 2>/dev/null | head -10
fi
```

For each session file, extract only the first 10 user messages to understand what the session was about:

```bash
python3 -c "
import json, sys
count = 0
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        d = json.loads(line)
        if d.get('type') != 'user': continue
        msg = d.get('message', {})
        content = msg.get('content', [])
        if isinstance(content, str):
            texts = [content]
        elif isinstance(content, list):
            texts = [c.get('text','') for c in content if isinstance(c,dict) and c.get('type')=='text']
        else:
            continue
        for text in texts:
            text = text.strip()
            if text:
                print(text[:200])
                count += 1
                if count >= 10: sys.exit()
" <session_file>
```

Based on the first 10 user messages, write a one-line summary for each session (e.g., "调试 OOM 问题并定位到 GatewayClient 内存泄漏"). **Decide which sessions are worth deeper extraction** — skip sessions that are simple Q&A, trivial edits, or unrelated to the current /ax prompt.

**Level 2: Deep extract — full text from selected sessions only**

For each session selected in Level 1 (typically 1-3), extract all user and assistant text:

```bash
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        d = json.loads(line)
        t = d.get('type')
        if t not in ('user', 'assistant'): continue
        msg = d.get('message', {})
        content = msg.get('content', [])
        if isinstance(content, str):
            texts = [content]
        elif isinstance(content, list):
            texts = [c.get('text','') for c in content if isinstance(c,dict) and c.get('type')=='text']
        else:
            continue
        for text in texts:
            text = text.strip()
            if not text: continue
            if len(text) > 500:
                text = text[:500] + '...[truncated]'
            print(f'[{t}] {text}')
" <session_file>
```

This extracts only user questions and assistant conclusions — skipping tool calls, tool results, file snapshots, and other noise. From the extracted text, identify:
- Key decisions and the reasoning behind them
- Root causes found during debugging
- Solutions applied and why
- Non-obvious gotchas or constraints discovered

Skip sessions that produce fewer than 10 meaningful messages (trivially short).

### Step 2: Analyze & Extract

Based on collected data, identify knowledge worth saving:

| Type | Target Path | When |
|------|------------|------|
| Architecture knowledge | `docs/ai-context/{topic}.md` | Core design, data flow, system principles |
| Project skill | `.agents/skills/{name}/SKILL.md` | Repeatable workflows: debugging, deployment, review |
| Module documentation | `{module}/AGENTS.md` append | Module-specific context, APIs, gotchas |

**If user provided a prompt:** Focus extraction around that topic.
**If no prompt:** Scan broadly, recommend what to save.

For each piece of knowledge:
- Determine the type and target path
- Draft the content
- Keep each file under 200 lines

### Step 3: Preview & Confirm

For each file to be written, show the user:

1. **Target path** — where the file will be created/updated
2. **Content preview** — the full content to be written
3. **Rationale** — why this knowledge is worth saving

Ask the user to confirm before writing. Use AskUserQuestion:
- "Write this file?" with options: Yes / Skip / Edit first

**Do NOT write any file without explicit user confirmation.**

### Step 4: Validate (run bash commands, not self-check)

For each file to be written, run these validation commands BEFORE writing. Do NOT skip any step.

**4a. Line count gate (hard block)**

```bash
echo "<draft content>" | wc -l
```

If output > 200: **STOP. Do not write.** Split into multiple files with @ references, then re-validate each piece.

**4b. Duplication scan (bash search + human judgment)**

```bash
grep -rl "<2-3 core keywords from draft>" docs/ai-context/ .agents/skills/ 2>/dev/null || echo "no duplicates"
```

If files are found: read them. If content overlaps, update the existing file instead of creating a new one.

**4c. @ reference validity (hard block)**

```bash
# Extract all @ references from draft, verify each path exists
for ref in $(echo "<draft content>" | grep -oP '@[\w/.,-]+\.\w+' | sed 's/^@//'); do
  test -f "$ref" || echo "BROKEN: $ref"
done
```

If any BROKEN: fix the reference or ensure the target file will be created in this same operation. Do not write files with broken @ references.

**4d. Actionable content (prompt-level, cannot be automated)**

Review the draft: does it contain specific commands, file paths, code patterns, or step-by-step procedures? Vague advice fails this check.

- Bad: "be careful with caching"
- Good: "set `max-old-space-size=4096` when processing datasets > 1GB"

### Step 5: Write Files

For confirmed files:

1. Write the file content
2. Update the nearest parent `AGENTS.md` with an `@` reference to the new file:
```markdown
## Deep Dive Docs
- @docs/ai-context/new-topic.md — Brief description
```
3. If `AGENTS.md` doesn't exist at the project root, create one with the template (including `@.ax/RULES.md` reference)
4. If `CLAUDE.md` doesn't exist, create it as symlink or pointer to AGENTS.md

### Step 6: Summary

Report what was saved:
- Files written/updated with paths
- Files skipped (user declined)
- Remind user to review and commit via git when ready

**Do NOT auto-commit.** Git operations are fully user-controlled.

## Output Conventions

### File Constraints
- Each markdown file: max 200 lines
- Use `@` references to link related docs
- Follow existing project structure if AGENTS.md hierarchy exists

### Multi-tool Compatibility

| Tool | Instruction file | Skill directory | Compatibility |
|------|-----------------|-----------------|---------------|
| Claude Code | CLAUDE.md | .claude/skills/ | Symlink or pointer to AGENTS.md |
| Codex | AGENTS.md | .agents/skills/ | Native |
| Cursor | .cursorrules | — | @ reference AGENTS.md |

### AGENTS.md Structure Template

```markdown
# {Project Name}

## Instructions

### AGENTS.md 读取规则
修改或设计涉及某目录的代码前，必须先读该目录及父目录的 AGENTS.md。

### 知识沉淀

完成复杂任务后，主动判断是否沉淀：skill → .agents/skills/，知识 → docs/ai-context/，模块 → AGENTS.md。
发现已有文档过时时立即更新。详见 @.ax/RULES.md。

## Quick Start
Key commands and setup.

## Architecture
High-level architecture summary.

## Module Index
- @{module}/AGENTS.md — Module description

## Deep Dive Docs
- @docs/ai-context/{topic}.md — Topic description
```

### Skill Template

```markdown
---
name: {skill-name}
description: "{When to use this skill}"
---

# {Skill Title}

## When to Use
Trigger conditions.

## Steps
1. Step one
2. Step two

## Examples
Concrete examples.
```

## Key Principles

- **Human in the loop** — every write requires confirmation
- **Under 200 lines** — split large docs, use @ references
- **Git-native** — no auto-commit, user controls versioning
