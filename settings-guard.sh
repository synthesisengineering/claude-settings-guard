#!/bin/bash
# claude-settings-guard — Protects Claude Code settings from unauthorized changes.
# https://github.com/rajivpant/claude-settings-guard
#
# Runs as a UserPromptSubmit hook. Checks that effortLevel, alwaysThinkingEnabled,
# and its own hook registration are intact. Optionally auto-fixes tampered settings.

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
CONF_FILE="$HOME/.claude/settings-guard.conf"
LOG_FILE="$HOME/.claude/settings-guard.log"
SCRIPT_NAME="settings-guard.sh"
HOOK_COMMAND="~/.claude/settings-guard.sh"

# ─── Defaults (overridden by conf file) ─────────────────────────────────────

MIN_EFFORT="max"
REQUIRE_THINKING="true"
AUTO_FIX="false"

# ─── Load config ────────────────────────────────────────────────────────────

load_config() {
  if [ -f "$CONF_FILE" ]; then
    while IFS='=' read -r key value; do
      key=$(echo "$key" | tr -d '[:space:]')
      value=$(echo "$value" | tr -d '[:space:]')
      [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
      case "$key" in
        MIN_EFFORT) MIN_EFFORT="$value" ;;
        REQUIRE_THINKING) REQUIRE_THINKING="$value" ;;
        AUTO_FIX) AUTO_FIX="$value" ;;
        LOG_FILE) LOG_FILE="$value" ;;
      esac
    done < "$CONF_FILE"
  fi
}

# ─── Logging ─────────────────────────────────────────────────────────────────

log_event() {
  local msg="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

# ─── Settings read/write ─────────────────────────────────────────────────────

read_setting() {
  local key="$1"
  python3 -c "
import json, sys
try:
    d = json.load(open('$SETTINGS_FILE'))
    v = d.get('$key')
    if v is None:
        print('NOT SET')
    elif isinstance(v, bool):
        print(str(v).lower())
    else:
        print(v)
except Exception:
    print('ERROR')
" 2>/dev/null
}

write_setting() {
  local key="$1" value="$2" is_bool="${3:-false}"
  python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    d = json.load(f)
if '$is_bool' == 'true':
    d['$key'] = True if '$value' == 'true' else False
else:
    d['$key'] = '$value'
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" 2>/dev/null
}

# ─── Hook integrity check ───────────────────────────────────────────────────

check_hook_registered() {
  python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    d = json.load(f)
hooks = d.get('hooks', {})
user_hooks = hooks.get('UserPromptSubmit', [])
for group in user_hooks:
    for h in group.get('hooks', []):
        if '$HOOK_COMMAND' in h.get('command', ''):
            print('registered')
            exit(0)
print('missing')
" 2>/dev/null
}

# ─── Health check (--status) ────────────────────────────────────────────────

show_status() {
  echo "claude-settings-guard — health check"
  echo ""

  # Script exists
  if [ -f "$HOME/.claude/$SCRIPT_NAME" ]; then
    echo "  Script:     installed at ~/.claude/$SCRIPT_NAME"
  else
    echo "  Script:     MISSING — reinstall needed"
  fi

  # Config file
  if [ -f "$CONF_FILE" ]; then
    echo "  Config:     $CONF_FILE"
  else
    echo "  Config:     using defaults (no conf file)"
  fi

  # Settings file
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo "  Settings:   MISSING — $SETTINGS_FILE not found"
    exit 1
  fi

  # Hook registered
  local hook_status
  hook_status=$(check_hook_registered)
  if [ "$hook_status" = "registered" ]; then
    echo "  Hook:       registered in settings.json"
  else
    echo "  Hook:       NOT REGISTERED — guard is not running"
  fi

  # Effort level
  local effort
  effort=$(read_setting "effortLevel")
  if [ "$effort" = "$MIN_EFFORT" ]; then
    echo "  Effort:     $effort (meets minimum: $MIN_EFFORT)"
  else
    echo "  Effort:     $effort (BELOW minimum: $MIN_EFFORT)"
  fi

  # Thinking mode
  local thinking
  thinking=$(read_setting "alwaysThinkingEnabled")
  if [ "$REQUIRE_THINKING" = "true" ]; then
    if [ "$thinking" = "true" ]; then
      echo "  Thinking:   enabled"
    else
      echo "  Thinking:   DISABLED (required by config)"
    fi
  else
    echo "  Thinking:   $thinking (not enforced)"
  fi

  # Env var
  if [ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]; then
    echo "  Env var:    CLAUDE_CODE_EFFORT_LEVEL=$CLAUDE_CODE_EFFORT_LEVEL"
  else
    echo "  Env var:    CLAUDE_CODE_EFFORT_LEVEL not set"
  fi

  # Log file
  if [ -f "$LOG_FILE" ]; then
    local count
    count=$(wc -l < "$LOG_FILE" | tr -d ' ')
    echo "  Log:        $LOG_FILE ($count entries)"
  else
    echo "  Log:        no events recorded yet"
  fi

  echo ""
  exit 0
}

# ─── Fix command (--fix) ────────────────────────────────────────────────────

run_fix() {
  local fixed=0

  if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Settings file not found: $SETTINGS_FILE" >&2
    exit 1
  fi

  local effort
  effort=$(read_setting "effortLevel")
  if [ "$effort" != "$MIN_EFFORT" ]; then
    write_setting "effortLevel" "$MIN_EFFORT"
    echo "Fixed effortLevel: $effort -> $MIN_EFFORT"
    log_event "MANUAL FIX effortLevel: $effort -> $MIN_EFFORT"
    fixed=1
  fi

  if [ "$REQUIRE_THINKING" = "true" ]; then
    local thinking
    thinking=$(read_setting "alwaysThinkingEnabled")
    if [ "$thinking" != "true" ]; then
      write_setting "alwaysThinkingEnabled" "true" "true"
      echo "Fixed alwaysThinkingEnabled: $thinking -> true"
      log_event "MANUAL FIX alwaysThinkingEnabled: $thinking -> true"
      fixed=1
    fi
  fi

  if [ "$fixed" -eq 0 ]; then
    echo "All settings are correct. Nothing to fix."
  fi

  exit 0
}

# ─── Main guard logic ───────────────────────────────────────────────────────

main() {
  load_config

  # Handle CLI flags
  case "${1:-}" in
    --status) show_status ;;
    --fix) run_fix ;;
    --help)
      echo "Usage: $SCRIPT_NAME [--status|--fix|--help]"
      echo ""
      echo "  (no args)   Run as UserPromptSubmit hook (normal mode)"
      echo "  --status    Health check — show installation and settings state"
      echo "  --fix       Restore settings to configured values"
      echo "  --help      Show this help"
      exit 0
      ;;
  esac

  # Guard mode — called by the UserPromptSubmit hook
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Settings file not found: $SETTINGS_FILE" >&2
    exit 2
  fi

  local problems=()

  # Check effort level
  local effort
  effort=$(read_setting "effortLevel")
  if [ "$effort" != "$MIN_EFFORT" ]; then
    problems+=("effortLevel is '$effort' (required: '$MIN_EFFORT')")
  fi

  # Check thinking mode
  if [ "$REQUIRE_THINKING" = "true" ]; then
    local thinking
    thinking=$(read_setting "alwaysThinkingEnabled")
    if [ "$thinking" != "true" ]; then
      problems+=("alwaysThinkingEnabled is '$thinking' (required: 'true')")
    fi
  fi

  # Check env var if set
  if [ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ] && [ "$CLAUDE_CODE_EFFORT_LEVEL" != "$MIN_EFFORT" ]; then
    problems+=("CLAUDE_CODE_EFFORT_LEVEL env var is '$CLAUDE_CODE_EFFORT_LEVEL' (required: '$MIN_EFFORT')")
  fi

  # Check hook self-integrity
  local hook_status
  hook_status=$(check_hook_registered)
  if [ "$hook_status" != "registered" ]; then
    problems+=("settings-guard hook has been removed from settings.json")
  fi

  # No problems — pass silently
  if [ ${#problems[@]} -eq 0 ]; then
    exit 0
  fi

  # Problems found — log them
  for p in "${problems[@]}"; do
    log_event "DETECTED $p"
  done

  # Auto-fix if enabled
  if [ "$AUTO_FIX" = "true" ]; then
    if [ "$effort" != "$MIN_EFFORT" ]; then
      write_setting "effortLevel" "$MIN_EFFORT"
      log_event "AUTO-FIXED effortLevel: $effort -> $MIN_EFFORT"
    fi
    if [ "$REQUIRE_THINKING" = "true" ]; then
      local thinking
      thinking=$(read_setting "alwaysThinkingEnabled")
      if [ "$thinking" != "true" ]; then
        write_setting "alwaysThinkingEnabled" "true" "true"
        log_event "AUTO-FIXED alwaysThinkingEnabled: $thinking -> true"
      fi
    fi
    # Re-check after fix — only block if something couldn't be fixed
    local remaining=()
    effort=$(read_setting "effortLevel")
    [ "$effort" != "$MIN_EFFORT" ] && remaining+=("effortLevel still '$effort' after auto-fix attempt")
    if [ "$REQUIRE_THINKING" = "true" ]; then
      thinking=$(read_setting "alwaysThinkingEnabled")
      [ "$thinking" != "true" ] && remaining+=("alwaysThinkingEnabled still '$thinking' after auto-fix attempt")
    fi
    if [ ${#remaining[@]} -eq 0 ]; then
      # Fixed successfully — warn but don't block
      {
        echo "SETTINGS GUARD: Auto-fixed tampered settings. Check ~/.claude/settings-guard.log for details."
      } >&2
      exit 0
    fi
    problems=("${remaining[@]}")
  fi

  # Block the prompt
  {
    echo "SETTINGS GUARD: Your Claude Code settings have been changed."
    echo ""
    for p in "${problems[@]}"; do
      echo "  - $p"
    done
    echo ""
    echo "To fix: ~/.claude/settings-guard.sh --fix"
    echo "To review: ~/.claude/settings-guard.sh --status"
    echo "Audit log: $LOG_FILE"
  } >&2
  exit 2
}

main "$@"
