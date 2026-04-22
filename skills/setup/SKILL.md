---
name: setup
description: "Enable AX status line — adds sedimentation progress indicator to Claude Code's bottom bar"
---

# AX Setup — Enable Status Line

Add the AX status line to the **current project's** `.claude/settings.json`.

## Steps

### Step 1: Add statusLine to project settings

Read `.claude/settings.json` in the project root. Create the file and `.claude/` directory if they don't exist.

Merge this into the existing JSON (do NOT overwrite other keys):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/status-line.sh",
    "refreshInterval": 3
  }
}
```

`${CLAUDE_PLUGIN_ROOT}` is set by Claude Code at runtime — write it literally, do NOT resolve or replace it.

### Step 2: Confirm

Tell the user the status line is enabled and will appear on the next message.
