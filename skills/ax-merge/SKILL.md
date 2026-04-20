---
name: ax-merge
description: "AI-assisted merge for knowledge file conflicts — use after git pull/merge when docs/ai-context or .agents/skills files have conflicts."
---

# AX Merge — AI-Assisted Knowledge File Merge

Resolve merge conflicts in AX-generated knowledge documents using AI understanding of the content.

## When to Use

After `git pull` or `git merge` when conflicts appear in:
- `docs/ai-context/*.md`
- `.agents/skills/*/SKILL.md`
- `*/AGENTS.md`

## Workflow

### Step 1: Detect Conflicts

Scan knowledge directories for conflict markers:
```bash
grep -rl "<<<<<<" docs/ai-context/ .agents/skills/ */AGENTS.md 2>/dev/null
```

If no conflicts found, report "No knowledge file conflicts detected" and stop.

### Step 2: For Each Conflicted File

1. Read the file with conflict markers
2. Identify the two versions (ours vs theirs)
3. Understand the semantic content of both versions
4. Propose a merged version that:
   - Preserves all unique knowledge from both sides
   - Resolves contradictions by preferring the more recent/complete version
   - Maintains consistent structure and formatting
   - Keeps the file under 200 lines
   - Updates the `ax-meta` block with merged sources and current date

### Step 3: Preview & Confirm

Show the user:
- The conflicted file path
- Brief description of what each side changed
- The proposed merged content

Ask for confirmation before writing.

### Step 4: Write Resolved File

Write the merged content, removing all conflict markers.

### Step 5: Summary

Report which files were resolved and which were skipped.
Remind user to `git add` the resolved files and complete the merge.
