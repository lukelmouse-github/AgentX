#!/usr/bin/env python3
"""AX sedimentation evaluator — reads profile.yaml + accumulated signals, outputs true/false."""

import json
import os
import re
import sys

DEFAULT_PROFILE = {
    "signals": {
        "key_paths": [],
        "test_patterns": ["pytest", "npm test", "go test", "cargo test", "vitest", "jest", "make test"],
    },
    "triggers": [
        {"when": "tool_count >= 50 and write_count >= 5", "reason": "large-scale work with substantial edits"},
        {"when": "debug_signals >= 10 and write_count >= 3", "reason": "deep debugging session with fixes"},
        {"when": "test_runs >= 2 and write_count >= 5", "reason": "heavily tested multi-file changes"},
        {"when": "bash_count >= 15 and write_count >= 3", "reason": "heavy scripting with file changes"},
    ],
}

SAFE_NAMES = {
    "tool_count", "write_count", "read_count", "bash_count",
    "key_path_edits", "test_runs", "debug_signals",
}
SAFE_OPS = {">=", "<=", ">", "<", "==", "and", "or"}

DEBUG_KEYWORDS = re.compile(r"error|traceback|debug|fix|bug|failure|panic|exception", re.IGNORECASE)


# ── Mini YAML parser (handles our fixed 2-level subset) ──────────────

def parse_profile_yaml(text):
    """Parse the subset of YAML used by profile.yaml. No PyYAML dependency."""
    result = {}
    current_section = None
    current_key = None
    current_list = None

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        indent = len(raw_line) - len(raw_line.lstrip())

        # top-level key (indent 0): "project:", "signals:", "triggers:"
        if indent == 0 and stripped.endswith(":"):
            current_section = stripped[:-1]
            result[current_section] = {}
            current_key = None
            current_list = None
            continue

        if indent == 0 and ": " in stripped:
            key, val = stripped.split(": ", 1)
            result[key] = _yaml_val(val)
            current_section = None
            continue

        if current_section is None:
            continue

        # triggers is a list of dicts
        if current_section == "triggers":
            if isinstance(result[current_section], dict):
                result[current_section] = []
            if stripped.startswith("- when:"):
                entry = {"when": _yaml_val(stripped[len("- when:"):].strip())}
                result[current_section].append(entry)
                current_key = result[current_section][-1]
                continue
            if stripped.startswith("reason:") and isinstance(current_key, dict):
                current_key["reason"] = _yaml_val(stripped[len("reason:"):].strip())
                continue

        # second-level key: "  name: foo" or "  key_paths:"
        if indent >= 2 and ":" in stripped:
            if stripped.startswith("- "):
                # list item inside current_list
                if current_list is not None:
                    current_list.append(_yaml_val(stripped[2:]))
                continue

            key_part, _, val_part = stripped.partition(":")
            key_part = key_part.strip().lstrip("- ")
            val_part = val_part.strip()

            if val_part:
                result[current_section][key_part] = _yaml_val(val_part)
                current_list = None
            else:
                result[current_section][key_part] = []
                current_list = result[current_section][key_part]
            current_key = key_part
            continue

        # list item: "    - value"
        if stripped.startswith("- ") and current_list is not None:
            current_list.append(_yaml_val(stripped[2:]))

    return result


def _yaml_val(s):
    s = s.strip()
    if not s:
        return ""
    for q in ('"', "'"):
        if s.startswith(q) and s.endswith(q):
            return s[1:-1]
    if s.isdigit():
        return int(s)
    if s == "true":
        return True
    if s == "false":
        return False
    return s


# ── Signal aggregation ────────────────────────────────────────────────

def aggregate_signals(signal_path, profile):
    signals = _read_jsonl(signal_path)
    key_paths = profile.get("signals", {}).get("key_paths", [])
    test_patterns = profile.get("signals", {}).get("test_patterns", [])

    counts = {name: 0 for name in SAFE_NAMES}

    for sig in signals:
        tool = sig.get("tool", "")
        path = sig.get("path", "")
        cmd = sig.get("cmd", "")

        counts["tool_count"] += 1

        if tool in ("Write", "Edit"):
            counts["write_count"] += 1
            if path and any(path.startswith(kp) or ("/" + kp) in path for kp in key_paths):
                counts["key_path_edits"] += 1
        elif tool == "Read":
            counts["read_count"] += 1
        elif tool == "Bash":
            counts["bash_count"] += 1
            if cmd and any(tp in cmd for tp in test_patterns):
                counts["test_runs"] += 1
            if cmd and DEBUG_KEYWORDS.search(cmd):
                counts["debug_signals"] += 1

    return counts


def aggregate_from_transcript(transcript_path, profile):
    """Fallback: aggregate from transcript JSONL when no signal file exists."""
    counts = {name: 0 for name in SAFE_NAMES}
    if not transcript_path or not os.path.isfile(transcript_path):
        return counts

    test_patterns = profile.get("signals", {}).get("test_patterns", [])
    key_paths = profile.get("signals", {}).get("key_paths", [])

    try:
        with open(transcript_path, "r") as f:
            for line in f:
                if '"type":"tool_use"' in line or '"type": "tool_use"' in line:
                    counts["tool_count"] += 1
                    if '"name":"Write"' in line or '"name":"Edit"' in line or \
                       '"name": "Write"' in line or '"name": "Edit"' in line:
                        counts["write_count"] += 1
                        for kp in key_paths:
                            if kp in line:
                                counts["key_path_edits"] += 1
                                break
                    elif '"name":"Read"' in line or '"name": "Read"' in line:
                        counts["read_count"] += 1
                    elif '"name":"Bash"' in line or '"name": "Bash"' in line:
                        counts["bash_count"] += 1
                        for tp in test_patterns:
                            if tp in line:
                                counts["test_runs"] += 1
                                break
                        if DEBUG_KEYWORDS.search(line):
                            counts["debug_signals"] += 1
    except (OSError, UnicodeDecodeError):
        pass

    return counts


# ── Expression evaluator ──────────────────────────────────────────────

def eval_trigger(expr, variables):
    """Evaluate a when-expression against variable dict. Returns bool."""
    tokens = re.findall(r"[a-z_]+|\d+|>=|<=|==|>|<", expr)
    safe = []
    for tok in tokens:
        if tok in SAFE_NAMES:
            safe.append(str(variables.get(tok, 0)))
        elif tok.isdigit():
            safe.append(tok)
        elif tok in ("and", "or"):
            safe.append(tok)
        elif tok in (">=", "<=", ">", "<", "=="):
            safe.append(tok)
        else:
            return False
    try:
        return bool(eval(" ".join(safe), {"__builtins__": {}}, {}))  # noqa: S307
    except Exception:
        return False


# ── Utilities ─────────────────────────────────────────────────────────

def _read_jsonl(path):
    items = []
    if not path or not os.path.isfile(path):
        return items
    try:
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        items.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
    except OSError:
        pass
    return items


# ── Main ──────────────────────────────────────────────────────────────

def main():
    profile_path = sys.argv[1] if len(sys.argv) > 1 else ""
    signal_path = sys.argv[2] if len(sys.argv) > 2 else ""
    transcript_path = sys.argv[3] if len(sys.argv) > 3 else ""

    # Load profile
    profile = DEFAULT_PROFILE
    if profile_path and os.path.isfile(profile_path):
        try:
            with open(profile_path, "r") as f:
                profile = parse_profile_yaml(f.read())
        except (OSError, UnicodeDecodeError):
            profile = DEFAULT_PROFILE

    if "triggers" not in profile or not profile["triggers"]:
        profile["triggers"] = DEFAULT_PROFILE["triggers"]
    if "signals" not in profile:
        profile["signals"] = DEFAULT_PROFILE["signals"]

    # Aggregate signals
    if signal_path and os.path.isfile(signal_path):
        counts = aggregate_signals(signal_path, profile)
    else:
        counts = aggregate_from_transcript(transcript_path, profile)

    # Evaluate triggers
    for trigger in profile.get("triggers", []):
        expr = trigger.get("when", "")
        if expr and eval_trigger(expr, counts):
            print("true")
            return

    print("false")


if __name__ == "__main__":
    main()
