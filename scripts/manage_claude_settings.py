#!/usr/bin/env python3

import json
import sys
from pathlib import Path
from typing import Optional


MATCHER = "startup|clear|compact"
AX_HOOK_MARKER = ".ax/hooks/session-start"


def strip_json_comments(text: str) -> str:
    result = []
    in_string = False
    escape = False
    line_comment = False
    block_comment = False

    i = 0
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if line_comment:
            if ch == "\n":
                line_comment = False
                result.append(ch)
            i += 1
            continue

        if block_comment:
            if ch == "*" and nxt == "/":
                block_comment = False
                i += 2
            else:
                i += 1
            continue

        if in_string:
            result.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            i += 1
            continue

        if ch == '"':
            in_string = True
            result.append(ch)
            i += 1
            continue

        if ch == "/" and nxt == "/":
            line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            block_comment = True
            i += 2
            continue

        result.append(ch)
        i += 1

    return "".join(result)


def load_settings(path: Path) -> tuple[dict, str]:
    if not path.exists():
        return {}, ""

    raw = path.read_text()
    if not raw.strip():
        return {}, raw

    return json.loads(strip_json_comments(raw)), raw


def is_ax_hook(hook: dict) -> bool:
    return AX_HOOK_MARKER in hook.get("command", "")


def remove_ax_hooks(entries: list) -> list:
    kept_entries = []
    for entry in entries:
        hooks = entry.get("hooks", [])
        remaining_hooks = [
            hook for hook in hooks if not (isinstance(hook, dict) and is_ax_hook(hook))
        ]
        if remaining_hooks:
            updated_entry = dict(entry)
            updated_entry["hooks"] = remaining_hooks
            kept_entries.append(updated_entry)
    return kept_entries


def add_ax_hook(settings: dict, command: str) -> bool:
    hooks = settings.setdefault("hooks", {})
    start_entries = hooks.get("SessionStart", [])
    had_ax_hook = any(
        isinstance(hook, dict) and is_ax_hook(hook)
        for entry in start_entries
        for hook in entry.get("hooks", [])
    )
    normalized = remove_ax_hooks(start_entries)
    normalized.append(
        {
            "matcher": MATCHER,
            "hooks": [{"type": "command", "command": command, "async": False}],
        }
    )
    hooks["SessionStart"] = normalized
    return had_ax_hook


def remove_ax_hook(settings: dict) -> bool:
    hooks = settings.get("hooks", {})
    start_entries = hooks.get("SessionStart", [])
    had_ax_hook = any(
        isinstance(hook, dict) and is_ax_hook(hook)
        for entry in start_entries
        for hook in entry.get("hooks", [])
    )
    if not had_ax_hook:
        return False

    normalized = remove_ax_hooks(start_entries)
    if normalized:
        hooks["SessionStart"] = normalized
    else:
        hooks.pop("SessionStart", None)

    if not hooks:
        settings.pop("hooks", None)

    return True


def maybe_backup_original(path: Path, original_raw: str, rendered: str) -> Optional[Path]:
    if not path.exists():
        return None
    if not original_raw.strip():
        return None
    if original_raw == rendered:
        return None

    backup_path = path.with_name(path.name + ".ax.bak")
    for parent in path.parents:
        git_dir = parent / ".git"
        if git_dir.is_dir():
            backup_dir = git_dir / "ax-backups"
            backup_dir.mkdir(parents=True, exist_ok=True)
            backup_path = backup_dir / path.name
            break
    if backup_path.exists():
        return None

    backup_path.write_text(original_raw)
    return backup_path


def dump_settings(path: Path, settings: dict, original_raw: str) -> Optional[Path]:
    rendered = json.dumps(settings, indent=2, ensure_ascii=False) + "\n"
    backup_path = maybe_backup_original(path, original_raw, rendered)
    path.write_text(rendered)
    return backup_path


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: manage_claude_settings.py <add|remove> <settings_path> <hook_command>",
            file=sys.stderr,
        )
        return 1

    mode = sys.argv[1]
    path = Path(sys.argv[2])
    command = sys.argv[3]

    settings, original_raw = load_settings(path)

    if mode == "add":
        had_ax_hook = add_ax_hook(settings, command)
        backup_path = dump_settings(path, settings, original_raw)
        if backup_path is not None:
            print(f"[ax]   backed up original settings to {backup_path}")
        if had_ax_hook:
            print("[ax]   normalized hook: SessionStart")
        else:
            print("[ax]   added hook: SessionStart")
        return 0

    if mode == "remove":
        removed = remove_ax_hook(settings)
        if removed:
            backup_path = dump_settings(path, settings, original_raw)
            if backup_path is not None:
                print(f"[ax]   backed up original settings to {backup_path}")
            print("[ax]   removed SessionStart hook")
        else:
            print("[ax]   skip settings.json (no AX hook found)")
        return 0

    print(f"unknown mode: {mode}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
