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

### Step 1: Check Project Config

Check if `.ax.json` exists in the project root. If it contains `"enabled": false`, tell the user AX is disabled for this project and stop.

### Step 2: Detect Environment

Check claude-mem availability:
```bash
curl -s --max-time 2 http://localhost:37777/api/health
```

- **Available** → enhanced mode: can query historical observations
- **Unavailable** → basic mode: analyze current session context only

### Step 3: Collect Data

**Always available:**
- Current session context (conversation, files read/written, decisions made)
- Recent git changes: `git log --oneline -10` and `git diff --stat`

**Enhanced mode (claude-mem available):**
- Query relevant observations: `curl http://localhost:37777/api/observations?search=<topic>`
- Use semantic search to find related historical knowledge

**Note on claude-mem interaction:** AX is read-only with respect to claude-mem. However, claude-mem's hooks passively observe all session activity including AX execution, which may create meta-observations. This is a known trade-off; MVP does not address it since the noise is minimal and semantically low-ranked.

### Step 4: Analyze & Extract

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

### Step 5: Preview & Confirm

For each file to be written, show the user:

1. **Target path** — where the file will be created/updated
2. **Content preview** — the full content to be written
3. **Rationale** — why this knowledge is worth saving

Ask the user to confirm before writing. Use AskUserQuestion:
- "Write this file?" with options: Yes / Skip / Edit first

**Do NOT write any file without explicit user confirmation.**

### Step 6: Write Files

For confirmed files:

1. Write the file content
2. Append `ax-meta` comment at the end of each generated doc:
```markdown
<!-- ax-meta
sources:
  - path/to/relevant/source1.kt
  - path/to/relevant/source2.ts
generated: YYYY-MM-DD
-->
```
3. Update the nearest parent `AGENTS.md` with an `@` reference to the new file:
```markdown
## Deep Dive Docs
- @docs/ai-context/new-topic.md — Brief description
```
4. If `AGENTS.md` doesn't exist at the project root, create one with basic structure
5. If `CLAUDE.md` doesn't exist, create it as content pointing to AGENTS.md: `See AGENTS.md for project instructions.`

### Step 7: Update Timestamp

Record the current timestamp for incremental detection:
```bash
project_hash=$(printf '%s' "$PWD" | shasum -a 256 | cut -c1-16)
mkdir -p "${HOME}/.claude-ax/${project_hash}"
date +%s > "${HOME}/.claude-ax/${project_hash}/last_ax_ts"
```

### Step 8: Summary

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

## Overview
Brief project description.

## Quick Start
Key commands and setup.

## Architecture
High-level architecture summary.

## Module Index
- @{module}/AGENTS.md — Module description

## Deep Dive Docs
- @docs/ai-context/{topic}.md — Topic description

## Skills
- @.agents/skills/{name}/SKILL.md — Skill description
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
- **Incremental** — track what was already processed via timestamps
- **Graceful degradation** — works without claude-mem, better with it
