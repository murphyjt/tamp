#!/bin/bash
# tamp: after each reply, keep the Mac awake for 65 minutes (on power only) so
# Claude Code's idle compaction can run before the 1-hour prompt cache expires.
# Does nothing, and releases any timer, when the session can't idle-compact.
# `tamp.sh release` (SessionEnd hook) only releases the timer.
[ "$(uname)" = Darwin ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
sid=$(jq -r '.session_id // "unknown"' <<<"$input" 2>/dev/null)
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)

rundir="${XDG_STATE_HOME:-$HOME/.local/state}/tamp"
mkdir -p "$rundir" 2>/dev/null || exit 0
pidfile="$rundir/${sid:-unknown}.pid"

release_timer() {
  if [ -f "$pidfile" ]; then
    pid=$(cat "$pidfile")
    [ "$(ps -p "$pid" -o comm= 2>/dev/null)" = "caffeinate" ] && kill "$pid"
    rm -f "$pidfile"
  fi
}

[ "$1" = release ] && { release_timer; exit 0; }

is_number() { case $1 in ''|*[!0-9]*) return 1 ;; esac; }

# Project root: Claude Code's project dir, else the git root (only when the
# Command Line Tools are installed, so the stub git can't open an install dialog).
project=$CLAUDE_PROJECT_DIR
if [ -z "$project" ] && [ -n "$cwd" ] && xcode-select -p >/dev/null 2>&1; then
  project=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
fi
project=${project:-$cwd}

# Settings, lowest to highest precedence: user, project, local, managed.
setting() {
  value=""
  for f in "$HOME/.claude/settings.json" "$project/.claude/settings.json" \
           "$project/.claude/settings.local.json" \
           "/Library/Application Support/ClaudeCode/managed-settings.json"; do
    [ -f "$f" ] || continue
    v=$(jq -r --arg k "$1" 'if has($k) and .[$k] != null then .[$k] | tostring else empty end' "$f" 2>/dev/null)
    [ -n "$v" ] && value=$v
  done
  printf '%s' "$value"
}

# Idle compaction turned off.
if [ -n "$DISABLE_AUTO_COMPACT" ] || [ -n "$DISABLE_COMPACT" ] ||
   [ "$(setting idleCompaction)" = false ] || [ "$(setting autoCompactEnabled)" = false ]; then
  release_timer; exit 0
fi

# Needs the 1-hour cache: automatic on a subscription, opt-in elsewhere.
ttl=${CLAUDE_CODE_PROMPT_CACHE_TTL:-$(setting promptCacheTtl)}
if [ "$ttl" = 5m ]; then release_timer; exit 0; fi
if [ "$ttl" != 1h ] && { [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$ANTHROPIC_AUTH_TOKEN" ] ||
   [ -n "$CLAUDE_CODE_USE_BEDROCK" ] || [ -n "$CLAUDE_CODE_USE_VERTEX" ] ||
   [ -n "$CLAUDE_CODE_USE_FOUNDRY" ] || [ -n "$(setting apiKeyHelper)" ]; }; then
  release_timer; exit 0
fi

# Conversation must be at least the idle-compaction threshold.
threshold=${CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS:-200000}
is_number "$threshold" || threshold=200000
[ "$threshold" -lt 100000 ] && threshold=100000

tokens=0
if [ -f "$transcript" ]; then
  tokens=$(tail -n 500 "$transcript" | jq -R 'fromjson?
    | select(.type == "assistant" and .message.model != "<synthetic>") | .message.usage // empty
    | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
      + (.output_tokens // 0)' 2>/dev/null | tail -1)
fi
is_number "$tokens" || tokens=0
if [ "$tokens" -lt "$threshold" ]; then release_timer; exit 0; fi

release_timer
nohup caffeinate -s -t 3900 >/dev/null 2>&1 &
echo $! > "$pidfile"
