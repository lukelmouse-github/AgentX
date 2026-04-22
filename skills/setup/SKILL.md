---
name: setup
description: "Enable AX status line — adds sedimentation progress indicator to Claude Code's bottom bar"
---

# AX Setup — Enable Status Line

This skill configures the AX status line in your Claude Code settings.

## What It Does

Adds a persistent indicator at the bottom of your Claude Code terminal showing:

| Phase | Display | Meaning |
|-------|---------|---------|
| Accumulating | `AX  heavy ●○○  brain ○○○` | Progress toward auto-sedimentation trigger |
| Triggered | `AX ● triggered · debounce 42s` | Threshold met, waiting for activity to settle |
| Reviewing | `AX ⟳ reviewing transcript…` | Background LLM reading your session |
| Done | `AX ✓ sediment written · git diff to review` | Knowledge files written |
| Nothing | `AX · nothing to save` | Reviewed but nothing worth saving |

## Steps

### Step 1: Find the plugin root

```bash
# The status-line.sh script lives inside the ax plugin
AX_PLUGIN_ROOT=$(find ~/.claude/plugins ~/.claude/installed_plugins -maxdepth 3 -name "status-line.sh" -path "*/ax/*" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

# Fallback: if running from source
if [ -z "$AX_PLUGIN_ROOT" ]; then
  AX_PLUGIN_ROOT=$(find /Users -maxdepth 6 -path "*/ax/scripts/status-line.sh" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
fi

echo "AX scripts at: $AX_PLUGIN_ROOT"
```

### Step 2: Read current project settings

Read `.claude/settings.json` in the project root (create the file and directory if they don't exist). If it already has a `statusLine` entry, warn the user that this will replace it, and ask for confirmation.

### Step 3: Write the statusLine config

Add this to `.claude/settings.json` in the **project root** (NOT `~/.claude/settings.json` — the status line should only apply to this project):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <AX_PLUGIN_ROOT>/status-line.sh",
    "refreshInterval": 3
  }
}
```

Replace `<AX_PLUGIN_ROOT>` with the actual resolved path from Step 1.

Use the `Edit` tool to merge into existing settings — do not overwrite the file.

### Step 4: Confirm

Tell the user the status line is enabled. They will see it at the bottom of their terminal on the next message.
