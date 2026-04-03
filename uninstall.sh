#!/bin/bash
# claude-settings-guard uninstaller
# Removes all components installed by the installer.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# ─── Colors ──────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  GREEN='' YELLOW='' NC=''
fi

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

# ─── Remove hook from settings.json ─────────────────────────────────────────

if [ -f "$SETTINGS_FILE" ]; then
  python3 -c "
import json

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

changed = False
hooks = settings.get('hooks', {})
user_hooks = hooks.get('UserPromptSubmit', [])

# Remove groups containing our hook
new_groups = []
for group in user_hooks:
    new_hooks = [h for h in group.get('hooks', []) if 'settings-guard.sh' not in h.get('command', '')]
    if new_hooks:
        group['hooks'] = new_hooks
        new_groups.append(group)
    else:
        changed = True

if changed:
    if new_groups:
        hooks['UserPromptSubmit'] = new_groups
    else:
        hooks.pop('UserPromptSubmit', None)
    if not hooks:
        settings.pop('hooks', None)
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('removed')
else:
    print('not_found')
" | while read -r result; do
    if [ "$result" = "removed" ]; then
      info "Removed guard hook from settings.json"
    else
      info "Guard hook was not in settings.json (already clean)"
    fi
  done

  # Note: effortLevel and alwaysThinkingEnabled are LEFT in place.
  # These are user preferences, not guard-specific settings.
  warn "effortLevel and alwaysThinkingEnabled were left unchanged in settings.json"
else
  warn "No settings.json found — nothing to clean"
fi

# ─── Remove env var from shell rc file ───────────────────────────────────────

SHELL_NAME=$(basename "$SHELL")

remove_from_rc() {
  local rc_file="$1"
  if [ -f "$rc_file" ] && grep -qF "CLAUDE_CODE_EFFORT_LEVEL" "$rc_file"; then
    # Remove the env var line and the comment above it
    local tmp
    tmp=$(mktemp)
    grep -v "CLAUDE_CODE_EFFORT_LEVEL" "$rc_file" | grep -v "# Claude Code — enforce max effort level" > "$tmp"
    mv "$tmp" "$rc_file"
    info "Removed CLAUDE_CODE_EFFORT_LEVEL from $rc_file"
  fi
}

case "$SHELL_NAME" in
  zsh)  remove_from_rc "$HOME/.zshrc" ;;
  bash) remove_from_rc "$HOME/.bashrc"; remove_from_rc "$HOME/.bash_profile" ;;
  fish) remove_from_rc "$HOME/.config/fish/config.fish" ;;
esac

# ─── Remove guard files ─────────────────────────────────────────────────────

for f in settings-guard.sh settings-guard.conf settings-guard-uninstall.sh; do
  if [ -f "$CLAUDE_DIR/$f" ]; then
    rm "$CLAUDE_DIR/$f"
    info "Removed $CLAUDE_DIR/$f"
  fi
done

# Log file is kept intentionally — it's an audit trail
if [ -f "$CLAUDE_DIR/settings-guard.log" ]; then
  warn "Audit log kept at $CLAUDE_DIR/settings-guard.log (delete manually if desired)"
fi

echo ""
info "Uninstall complete."
