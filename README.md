# tamp

tamp keeps your Mac awake just long enough for Claude Code to compact an idle session. (Tamping is how you compact coffee before the shot.)

## Why

Claude Code has **idle compaction**: when a long conversation sits idle for about an hour, Claude Code summarizes it just before the 1-hour prompt cache expires. When you come back, your next message sends the short summary instead of re-caching the whole conversation, which uses less of your plan's usage.

Idle compaction only runs while the computer is awake. Most Macs sleep after 10–15 minutes without input, so it never gets the chance.

tamp is a pair of Claude Code hooks. After each reply, if the session can idle-compact, tamp runs `caffeinate -s` for 65 minutes. Each new reply restarts the timer. After 65 quiet minutes, or when the session ends, the Mac goes back to its normal sleep schedule.

tamp doesn't send tokens or touch the prompt cache. It only delays sleep.

## When tamp keeps the Mac awake

All of these must hold. Otherwise tamp does nothing and releases any timer it started.

- **macOS, on power.** `caffeinate -s` has no effect on battery.
- **The conversation is at least the idle-compaction threshold.** That's 200,000 tokens by default; `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS` changes it (minimum 100,000). tamp reads the size from the session transcript.
- **The session uses the 1-hour prompt cache.** That's automatic on a Claude subscription. API keys, `ANTHROPIC_AUTH_TOKEN`, `apiKeyHelper`, Bedrock, Vertex and Foundry default to the 5-minute cache, so tamp skips them unless `promptCacheTtl` is `"1h"` (or `CLAUDE_CODE_PROMPT_CACHE_TTL=1h`).
- **Idle compaction is on.** tamp skips sessions where `idleCompaction` or `autoCompactEnabled` is `false`, or `DISABLE_AUTO_COMPACT` / `DISABLE_COMPACT` is set. It reads user, project, local and managed settings.

## Install

Requirements: macOS and `jq`. `jq` ships with recent macOS at `/usr/bin/jq`; otherwise run `brew install jq`. Without `jq`, tamp does nothing.

1. Run `/plugin marketplace add murphyjt/tamp` in Claude Code.
2. Run `/plugin install tamp@tamp`.
3. Start a new session.

## Check it's working

In a session above the threshold, after a reply ends, run:

```sh
pmset -g assertions | grep -A1 caffeinate
```

Look for `PreventSystemSleep … caffeinate asserting for 3900 secs`. A `PreventUserIdleSystemSleep … 300 secs` entry belongs to Claude Code itself, which keeps the Mac awake while it's working.

## Limits

- **Closing the lid still sleeps the Mac** unless an external display is connected.
- **Subscriptions over their usage limit** drop to the 5-minute cache. tamp can't detect that, so it may keep the Mac awake for nothing in that case.
- **API-key users** can opt in with `promptCacheTtl: "1h"`, but 1-hour cache writes cost 2× the base input price (5-minute writes cost 1.25×). That only pays off if you often step away for 5–60 minutes in long sessions.
- **An `ANTHROPIC_API_KEY` you declined** at Claude Code's prompt still makes tamp skip the session. Set `CLAUDE_CODE_PROMPT_CACHE_TTL=1h` to override.
- **macOS only.** On Linux and Windows the hooks exit without doing anything.

## Turn it off

- Run `/plugin` and disable or uninstall `tamp`.
- To turn off idle compaction itself, set `"idleCompaction": false` in `~/.claude/settings.json`. tamp then stays idle too.

## License

MIT
