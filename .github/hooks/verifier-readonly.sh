#!/usr/bin/env bash
set -euo pipefail

python3 -c '
import json
import re
import sys

event = json.load(sys.stdin)
tool_name = str(event.get("tool_name", "")).lower()
tool_input = event.get("tool_input", {})

edit_markers = ("edit", "write", "create", "delete", "rename", "replace", "apply_patch")
denied = any(marker in tool_name for marker in edit_markers)
reason = f"verifier cannot invoke mutating tool {tool_name}"

commands = []
if isinstance(tool_input, dict):
    for key in ("command", "cmd", "script"):
        value = tool_input.get(key)
        if isinstance(value, str):
            commands.append(value)
command = "\n".join(commands)
mutation = re.compile(
    r"(^|[;&|]\s*)(rm|mv|cp|touch|mkdir|rmdir|truncate|install|chmod|chown)\b"
    r"|\bsed\s+[^\n]*-[A-Za-z]*i\b"
    r"|(^|[^<])>{1,2}\s*[^&]"
    r"|\|\s*tee\b"
    r"|\bgit\s+(add|apply|branch|checkout|cherry-pick|clean|commit|merge|rebase|reset|restore|revert|switch|tag|worktree\s+(add|move|remove))\b"
    r"|\b(npm|pnpm|yarn|pip|pip3)\s+(add|install|remove|uninstall)\b",
    re.IGNORECASE | re.MULTILINE,
)
if command and mutation.search(command):
    denied = True
    reason = "verifier execute command appears to mutate files or git state"

if denied:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
'