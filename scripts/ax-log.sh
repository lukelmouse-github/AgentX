#!/usr/bin/env bash
# AX logging utility — circular log to ~/.ax/log.log (max 300 lines)

AX_LOG_FILE="${HOME}/.ax/log.log"
AX_LOG_MAX=300

ax_log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  mkdir -p "$(dirname "$AX_LOG_FILE")"

  if [ ! -f "$AX_LOG_FILE" ]; then
    echo "$msg" > "$AX_LOG_FILE"
    return
  fi

  local current_lines
  current_lines=$(wc -l < "$AX_LOG_FILE" 2>/dev/null || echo 0)

  if [ "$current_lines" -ge "$AX_LOG_MAX" ]; then
    # Keep last 200 lines, then append
    local tmp="${AX_LOG_FILE}.tmp"
    tail -200 "$AX_LOG_FILE" > "$tmp" 2>/dev/null
    mv "$tmp" "$AX_LOG_FILE"
  fi

  echo "$msg" >> "$AX_LOG_FILE"
}
