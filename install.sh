#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
RULES_DIR="$CLAUDE_DIR/rules"
SKILLS_DIR="$CLAUDE_DIR/skills"
COMMANDS_DIR="$CLAUDE_DIR/commands"

echo "Installing claude-code-config..."

# Ensure target directories exist
mkdir -p "$RULES_DIR"
mkdir -p "$SKILLS_DIR"
mkdir -p "$COMMANDS_DIR"
mkdir -p "$CLAUDE_DIR"

# ──────────────────────────────────────────────
# 1. CLAUDE.md
# ──────────────────────────────────────────────
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  BACKUP="$CLAUDE_DIR/CLAUDE.backup.$(date +%Y%m%d_%H%M%S).md"
  cp "$CLAUDE_DIR/CLAUDE.md" "$BACKUP"
  echo "  Backed up existing CLAUDE.md → $BACKUP"
fi
cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
echo "  Installed CLAUDE.md"

# ──────────────────────────────────────────────
# 2. settings.json
# ──────────────────────────────────────────────
SETTINGS_SRC="$REPO_DIR/settings.json"
SETTINGS_DEST="$CLAUDE_DIR/settings.json"

if [ -f "$SETTINGS_SRC" ]; then
  if [ -f "$SETTINGS_DEST" ]; then
    BACKUP="$CLAUDE_DIR/settings.backup.$(date +%Y%m%d_%H%M%S).json"
    cp "$SETTINGS_DEST" "$BACKUP"
    echo "  Backed up existing settings.json → $BACKUP"
  fi

  cp "$SETTINGS_SRC" "$SETTINGS_DEST"
  echo "  Installed settings.json"

  # Replace hardcoded home directory paths with current user's $HOME
  if [[ "$HOME" != "/Users/MacBook" ]]; then
    sed -i '' "s|/Users/MacBook|$HOME|g" "$SETTINGS_DEST"
    echo "  Adjusted home directory paths in settings.json"
  fi

  # Repair iTerm2 integration symlinks when iTerm2 is installed
  ITERM_CC="/Applications/iTerm.app/Contents/Resources/utilities/cc-status"
  ITERM_CONFIG_DIR="$HOME/.config/iterm2"
  ITERM_APPSUPPORT="$HOME/Library/Application Support/iTerm2"

  if [ -f "$ITERM_CC" ]; then
    mkdir -p "$ITERM_CONFIG_DIR"

    if [ ! -L "$ITERM_CONFIG_DIR/cc-status" ] || [ ! -e "$ITERM_CONFIG_DIR/cc-status" ]; then
      ln -sf "$ITERM_CC" "$ITERM_CONFIG_DIR/cc-status"
      echo "  Fixed symlink: $ITERM_CONFIG_DIR/cc-status → $ITERM_CC"
    fi

    if [ ! -L "$ITERM_CONFIG_DIR/AppSupport" ] || [ ! -e "$ITERM_CONFIG_DIR/AppSupport" ]; then
      ln -sf "$ITERM_APPSUPPORT" "$ITERM_CONFIG_DIR/AppSupport"
      echo "  Fixed symlink: $ITERM_CONFIG_DIR/AppSupport → $ITERM_APPSUPPORT"
    fi
  fi

  sed -i '' "s|__HOME__|$HOME|g" "$SETTINGS_DEST"
  # Hooks always use portable statusline-command.sh — never iTerm2 binary path directly
  # statusLine.command also uses local statusline-command.sh
  sed -i '' "s|__STATUSLINE_CMD__|$CLAUDE_DIR/statusline-command.sh|g" "$SETTINGS_DEST"
  echo "  Hook command:       $CLAUDE_DIR/statusline-command.sh"
  echo "  StatusLine command: $CLAUDE_DIR/statusline-command.sh"
  echo "  Verification — unique hook commands written:"
  grep '"command"' "$SETTINGS_DEST" | grep -v '"node"\|"jq -r\|bash\|wc -l\|echo\|printf' | sort -u | sed 's/^[[:space:]]*/    /'
fi

# ──────────────────────────────────────────────
# 3. Rules
# ──────────────────────────────────────────────
RULE_INSTALLED=0
for rule in "$REPO_DIR/rules/"*.md; do
  [ -f "$rule" ] || continue
  filename="$(basename "$rule")"
  cp "$rule" "$RULES_DIR/$filename"
  echo "  Installed rules/$filename"
  RULE_INSTALLED=$((RULE_INSTALLED + 1))
done

# ──────────────────────────────────────────────
# 4. Skills
# ──────────────────────────────────────────────
SKILL_INSTALLED=0
for skill in "$REPO_DIR/skills/"*; do
  [ -e "$skill" ] || continue
  filename="$(basename "$skill")"
  dest="$SKILLS_DIR/$filename"
  rm -rf "$dest" 2>/dev/null
  cp -R "$skill" "$dest"
  echo "  Installed skills/$filename"
  SKILL_INSTALLED=$((SKILL_INSTALLED + 1))
done

# ──────────────────────────────────────────────
# 5. Commands
# ──────────────────────────────────────────────
CMD_INSTALLED=0
for cmd in "$REPO_DIR/commands/"*.md; do
  [ -f "$cmd" ] || continue
  filename="$(basename "$cmd")"
  cp "$cmd" "$COMMANDS_DIR/$filename"
  echo "  Installed commands/$filename"
  CMD_INSTALLED=$((CMD_INSTALLED + 1))
done

# ──────────────────────────────────────────────
# 6. Scripts (hooks / statusline)
# ──────────────────────────────────────────────
SCRIPT_INSTALLED=0
SCRIPTS_SRC_DIR="$REPO_DIR/scripts"
if [ -d "$SCRIPTS_SRC_DIR" ]; then
  for script in "$SCRIPTS_SRC_DIR/"*.sh; do
    [ -f "$script" ] || continue
    filename="$(basename "$script")"
    dest="$CLAUDE_DIR/$filename"
    cp "$script" "$dest"
    chmod +x "$dest"
    echo "  Installed scripts/$filename"
    SCRIPT_INSTALLED=$((SCRIPT_INSTALLED + 1))
  done
fi

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo ""
echo "Done. $RULE_INSTALLED rule(s), $SKILL_INSTALLED skill(s), $CMD_INSTALLED command(s), $SCRIPT_INSTALLED script(s) installed."
