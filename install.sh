#!/bin/bash
# claude-settings-guard installer
# Usage: curl -fsSL https://raw.githubusercontent.com/synthesisengineering/claude-settings-guard/main/install.sh | bash
#
# What this does:
# 1. Downloads settings-guard.sh to ~/.claude/
# 2. Creates a default config at ~/.claude/settings-guard.conf (if none exists)
# 3. Merges the UserPromptSubmit hook into your existing ~/.claude/settings.json
# 4. Sets effortLevel=max and alwaysThinkingEnabled=true (if not already set)
# 5. Adds CLAUDE_CODE_EFFORT_LEVEL=max to your shell rc file (if not already present)
# 6. Runs a health check to verify the installation

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SCRIPT_NAME="settings-guard.sh"
CONF_NAME="settings-guard.conf"
REPO_BASE="https://raw.githubusercontent.com/synthesisengineering/claude-settings-guard/main"

# ─── Colors (if terminal supports them) ─────────────────────────────────────

if [ -t 1 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' YELLOW='' RED='' BOLD='' NC=''
fi

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; }

# ─── Pre-flight checks ──────────────────────────────────────────────────────

if ! command -v python3 &>/dev/null; then
  error "python3 is required but not found. Install Python 3 and retry."
  exit 1
fi

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
  error "curl or wget is required but neither was found."
  exit 1
fi

# ─── Download function ──────────────────────────────────────────────────────

download() {
  local url="$1" dest="$2"
  if command -v curl &>/dev/null; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -q "$url" -O "$dest"
  fi
}

# ─── Step 1: Download the guard script ──────────────────────────────────────

info "Downloading settings-guard.sh..."
mkdir -p "$CLAUDE_DIR"

download "$REPO_BASE/$SCRIPT_NAME" "$CLAUDE_DIR/$SCRIPT_NAME"
chmod +x "$CLAUDE_DIR/$SCRIPT_NAME"
info "Installed $CLAUDE_DIR/$SCRIPT_NAME"

# ─── Step 2: Create default config (if none exists) ─────────────────────────

if [ ! -f "$CLAUDE_DIR/$CONF_NAME" ]; then
  download "$REPO_BASE/${CONF_NAME}.default" "$CLAUDE_DIR/$CONF_NAME"
  info "Created default config at $CLAUDE_DIR/$CONF_NAME"
else
  info "Config already exists at $CLAUDE_DIR/$CONF_NAME (not overwritten)"
fi

# ─── Step 3: Copy uninstall script ──────────────────────────────────────────

download "$REPO_BASE/uninstall.sh" "$CLAUDE_DIR/settings-guard-uninstall.sh"
chmod +x "$CLAUDE_DIR/settings-guard-uninstall.sh"

# ─── Step 4: Merge hook into settings.json ──────────────────────────────────

info "Configuring settings.json..."

if [ ! -f "$SETTINGS_FILE" ]; then
  # No settings file — create one
  python3 -c "
import json
settings = {
    'effortLevel': 'max',
    'alwaysThinkingEnabled': True,
    'hooks': {
        'UserPromptSubmit': [{
            'matcher': '',
            'hooks': [{
                'type': 'command',
                'command': '~/.claude/settings-guard.sh',
                'timeout': 5,
                'statusMessage': 'Checking settings integrity...'
            }]
        }]
    }
}
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
"
  info "Created $SETTINGS_FILE with guard hook"
else
  # Merge into existing settings
  python3 -c "
import json, sys

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

changed = False

# Set effortLevel if not max
if settings.get('effortLevel') != 'max':
    settings['effortLevel'] = 'max'
    changed = True

# Set alwaysThinkingEnabled if not true
if settings.get('alwaysThinkingEnabled') is not True:
    settings['alwaysThinkingEnabled'] = True
    changed = True

# Add hook if not present
hooks = settings.setdefault('hooks', {})
user_hooks = hooks.setdefault('UserPromptSubmit', [])

# Check if our hook is already registered
guard_registered = False
for group in user_hooks:
    for h in group.get('hooks', []):
        if '~/.claude/settings-guard.sh' in h.get('command', ''):
            guard_registered = True
            break

if not guard_registered:
    user_hooks.append({
        'matcher': '',
        'hooks': [{
            'type': 'command',
            'command': '~/.claude/settings-guard.sh',
            'timeout': 5,
            'statusMessage': 'Checking settings integrity...'
        }]
    })
    changed = True

if changed:
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('merged')
else:
    print('already_configured')
" | while read -r result; do
    if [ "$result" = "merged" ]; then
      info "Merged guard hook and settings into $SETTINGS_FILE"
    else
      info "Settings already configured (no changes needed)"
    fi
  done
fi

# ─── Step 5: Add env var to shell rc file ────────────────────────────────────

ENV_LINE='export CLAUDE_CODE_EFFORT_LEVEL=max'
SHELL_NAME=$(basename "$SHELL")
RC_FILE=""

case "$SHELL_NAME" in
  zsh)  RC_FILE="$HOME/.zshrc" ;;
  bash)
    if [ -f "$HOME/.bashrc" ]; then
      RC_FILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      RC_FILE="$HOME/.bash_profile"
    else
      RC_FILE="$HOME/.bashrc"
    fi
    ;;
  fish) RC_FILE="$HOME/.config/fish/config.fish" ;;
  *)    RC_FILE="" ;;
esac

if [ -n "$RC_FILE" ]; then
  if [ -f "$RC_FILE" ] && grep -qF "CLAUDE_CODE_EFFORT_LEVEL" "$RC_FILE"; then
    info "Env var already set in $RC_FILE"
  else
    echo "" >> "$RC_FILE"
    if [ "$SHELL_NAME" = "fish" ]; then
      echo "set -gx CLAUDE_CODE_EFFORT_LEVEL max" >> "$RC_FILE"
    else
      echo "# Claude Code — enforce max effort level" >> "$RC_FILE"
      echo "$ENV_LINE" >> "$RC_FILE"
    fi
    info "Added CLAUDE_CODE_EFFORT_LEVEL=max to $RC_FILE"
  fi
else
  warn "Could not detect shell rc file. Manually add: $ENV_LINE"
fi

# ─── Step 6: Verify installation ────────────────────────────────────────────

echo ""
"$CLAUDE_DIR/$SCRIPT_NAME" --status

echo ""
info "Installation complete."
echo ""
echo "  To customize:  edit ~/.claude/settings-guard.conf"
echo "  To check:      ~/.claude/settings-guard.sh --status"
echo "  To fix:        ~/.claude/settings-guard.sh --fix"
echo "  To uninstall:  ~/.claude/settings-guard-uninstall.sh"
echo ""
