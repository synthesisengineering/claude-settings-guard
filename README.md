# claude-settings-guard

Protects your [Claude Code](https://docs.anthropic.com/en/docs/claude-code) settings from being silently changed without your knowledge or consent.

## The problem

Claude Code has settings that control output quality — `effortLevel` and `alwaysThinkingEnabled`. These settings can be changed without notification, resulting in degraded responses that are hard to trace back to a configuration change.

## What this does

Three layers of protection:

1. **UserPromptSubmit hook** — checks your settings on every prompt. If `effortLevel` or `alwaysThinkingEnabled` have been changed, it blocks the prompt and tells you exactly what happened.
2. **Environment variable** — sets `CLAUDE_CODE_EFFORT_LEVEL` in your shell config, which takes precedence over `settings.json`.
3. **Audit log** — every detected change is logged with timestamps to `~/.claude/settings-guard.log`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/rajivpant/claude-settings-guard/main/install.sh | bash
```

The installer:
- Downloads `settings-guard.sh` to `~/.claude/`
- Creates a config file at `~/.claude/settings-guard.conf`
- Merges the hook into your existing `~/.claude/settings.json` (preserves all your other settings)
- Sets `effortLevel` to `max` and `alwaysThinkingEnabled` to `true`
- Adds `CLAUDE_CODE_EFFORT_LEVEL=max` to your shell rc file (supports zsh, bash, fish)
- Runs a health check to verify the installation

### Requirements

- Claude Code (CLI or VS Code extension)
- Python 3 (used for JSON manipulation)
- curl or wget

## Uninstall

```bash
~/.claude/settings-guard-uninstall.sh
```

Removes the hook, script, config, and env var. Leaves `effortLevel` and `alwaysThinkingEnabled` in place (those are your preferences). Keeps the audit log.

## Configuration

Edit `~/.claude/settings-guard.conf`:

```bash
# Minimum effort level required.
# Valid values: max, high, medium, low
MIN_EFFORT=max

# Require extended thinking to be on.
REQUIRE_THINKING=true

# Auto-fix tampered settings instead of blocking.
# true:  settings are restored automatically and the change is logged.
# false: the prompt is blocked until you manually fix the settings.
AUTO_FIX=false

# Path to the audit log.
LOG_FILE=~/.claude/settings-guard.log
```

### Auto-fix mode

By default, the guard blocks your prompt when settings are wrong, requiring you to fix them manually. If you prefer automatic restoration:

```bash
AUTO_FIX=true
```

With auto-fix enabled, tampered settings are silently restored to your configured values. Every change and restoration is recorded in the audit log.

## Commands

```bash
# Health check — verify installation and current settings
~/.claude/settings-guard.sh --status

# Fix — restore settings to configured values
~/.claude/settings-guard.sh --fix

# Help
~/.claude/settings-guard.sh --help
```

## How it works

The guard runs as a [Claude Code hook](https://docs.anthropic.com/en/docs/claude-code/hooks) on the `UserPromptSubmit` event — before every prompt you send to Claude. It checks:

1. `effortLevel` in `~/.claude/settings.json` matches your configured minimum
2. `alwaysThinkingEnabled` is `true` (if enforced)
3. `CLAUDE_CODE_EFFORT_LEVEL` env var hasn't been changed
4. The guard's own hook is still registered (self-integrity check)

If any check fails and `AUTO_FIX` is off, the hook exits with code 2, which blocks the prompt. You'll see a message explaining what changed and how to fix it.

If `AUTO_FIX` is on, the settings are restored and the prompt proceeds. Either way, the event is logged.

## Audit log

Every detected change is appended to `~/.claude/settings-guard.log`:

```
[2026-04-02 14:30:15] DETECTED effortLevel is 'high' (required: 'max')
[2026-04-02 14:30:15] AUTO-FIXED effortLevel: high -> max
```

The log is preserved on uninstall so you have a record of every change.

## License

MIT
