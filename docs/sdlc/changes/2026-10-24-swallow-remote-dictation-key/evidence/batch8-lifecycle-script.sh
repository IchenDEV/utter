#!/bin/bash
# Independent verifier lifecycle helpers — remote VID/PID only
set -euo pipefail
MATCH='{"VendorID":10007,"ProductID":12984}'
LOG="$1"
DIST="/Users/chenli/.cursor/worktrees/opentype/remote-dictation-key/dist/Utter.app"
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }
remote_get() { hidutil property --matching "$MATCH" --get UserKeyMapping 2>&1; }
internal_get() { hidutil property --matching '{"VendorID":1452,"PrimaryUsagePage":1,"PrimaryUsage":6}' --get UserKeyMapping 2>&1; }
quit_utter() {
  if pgrep -x Utter >/dev/null; then
    osascript -e 'tell application id "com.opentype.voiceinput" to quit' 2>/dev/null || true
    sleep 2
    if pgrep -x Utter >/dev/null; then
      kill -TERM "$(pgrep -x Utter)" 2>/dev/null || true
      log "WARN quit via SIGTERM (not graceful)"
      sleep 1
    fi
  fi
}
open_dist() {
  open "$DIST"
}
wait_mapping_contains_f5() {
  local deadline=$((SECONDS+30))
  while (( SECONDS < deadline )); do
    if remote_get | rg -q '30064771134'; then return 0; fi
    sleep 0.5
  done
  return 1
}
wait_mapping_empty() {
  local deadline=$((SECONDS+15))
  while (( SECONDS < deadline )); do
    if remote_get | rg -q 'UserKeyMapping   \($'; then sleep 0.5; continue; fi
    if remote_get | rg -q '30064771134'; then sleep 0.5; continue; fi
    if remote_get | rg -qi 'null|\(\s*\)|Could not'; then return 0; fi
    sleep 0.5
  done
  return 1
}

log "=== lifecycle script start ==="
log "internal keyboard: $(internal_get | tr '\n' ' ')"
