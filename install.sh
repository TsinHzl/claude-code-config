#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
RULES_DIR="$CLAUDE_DIR/rules"
SKILLS_DIR="$CLAUDE_DIR/skills"
COMMANDS_DIR="$CLAUDE_DIR/commands"
FORCE=false

# Parse flags
for arg in "$@"; do
  case $arg in
    --force) FORCE=true ;;
  esac
done

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

if [ ! -f "$CLAUDE_DIR/CLAUDE.md" ] || [ "$FORCE" = true ]; then
  cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "  Installed CLAUDE.md"
else
  echo "  Skipped CLAUDE.md (already exists, use --force to overwrite)"
fi

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

  if [ ! -f "$SETTINGS_DEST" ] || [ "$FORCE" = true ]; then
    cp "$SETTINGS_SRC" "$SETTINGS_DEST"
    echo "  Installed settings.json"

    # Replace hardcoded home directory paths with current user's $HOME
    if [[ "$HOME" != "/Users/MacBook" ]]; then
      sed -i '' "s|/Users/MacBook|$HOME|g" "$SETTINGS_DEST"
      echo "  Adjusted home directory paths in settings.json"
    fi

    # Resolve __HOME__ placeholder and pick statusline hook command (for hooks only)
    ITERM_CC="/Applications/iTerm.app/Contents/Resources/utilities/cc-status"
    if [ -f "$ITERM_CC" ]; then
      HOOK_CMD="$ITERM_CC"
    else
      HOOK_CMD="$CLAUDE_DIR/statusline-command.sh"
    fi
    sed -i '' "s|__HOME__|$HOME|g" "$SETTINGS_DEST"
    # __HOME__ expansion turns hook placeholders into $HOME/.claude/statusline-command.sh — replace with resolved hook command
    sed -i '' "s|$HOME/.claude/statusline-command.sh|$HOOK_CMD|g" "$SETTINGS_DEST"
    # statusLine.command always uses the local statusline-command.sh (never iTerm2)
    sed -i '' "s|__STATUSLINE_CMD__|$CLAUDE_DIR/statusline-command.sh|g" "$SETTINGS_DEST"
    echo "  Hook command:       $HOOK_CMD"
    echo "  StatusLine command: $CLAUDE_DIR/statusline-command.sh"
  else
    echo "  Skipped settings.json (already exists, use --force to overwrite)"
  fi
fi
# ──────────────────────────────────────────────
# 3. Rules
# ──────────────────────────────────────────────
RULE_INSTALLED=0
RULE_SKIPPED=0
for rule in "$REPO_DIR/rules/"*.md; do
  [ -f "$rule" ] || continue
  filename="$(basename "$rule")"
  dest="$RULES_DIR/$filename"
  if [ ! -f "$dest" ] || [ "$FORCE" = true ]; then
    cp "$rule" "$dest"
    echo "  Installed rules/$filename"
    RULE_INSTALLED=$((RULE_INSTALLED + 1))
  else
    echo "  Skipped rules/$filename (already exists)"
    RULE_SKIPPED=$((RULE_SKIPPED + 1))
  fi
done

# ──────────────────────────────────────────────
# 4. Skills
# ──────────────────────────────────────────────
SKILL_INSTALLED=0
SKILL_SKIPPED=0
for skill in "$REPO_DIR/skills/"*; do
  [ -e "$skill" ] || continue
  filename="$(basename "$skill")"
  dest="$SKILLS_DIR/$filename"
  if [ ! -e "$dest" ] || [ "$FORCE" = true ]; then
    rm -rf "$dest" 2>/dev/null
    cp -R "$skill" "$dest"
    echo "  Installed skills/$filename"
    SKILL_INSTALLED=$((SKILL_INSTALLED + 1))
  else
    echo "  Skipped skills/$filename (already exists)"
    SKILL_SKIPPED=$((SKILL_SKIPPED + 1))
  fi
done

# ──────────────────────────────────────────────
# 5. Commands
# ──────────────────────────────────────────────
CMD_INSTALLED=0
CMD_SKIPPED=0
for cmd in "$REPO_DIR/commands/"*.md; do
  [ -f "$cmd" ] || continue
  filename="$(basename "$cmd")"
  dest="$COMMANDS_DIR/$filename"
  if [ ! -f "$dest" ] || [ "$FORCE" = true ]; then
    cp "$cmd" "$dest"
    echo "  Installed commands/$filename"
    CMD_INSTALLED=$((CMD_INSTALLED + 1))
  else
    echo "  Skipped commands/$filename (already exists)"
    CMD_SKIPPED=$((CMD_SKIPPED + 1))
  fi
done

# ──────────────────────────────────────────────
# 6. Scripts (hooks / statusline)
# ──────────────────────────────────────────────
SCRIPT_INSTALLED=0
SCRIPT_SKIPPED=0
SCRIPTS_SRC_DIR="$REPO_DIR/scripts"
if [ -d "$SCRIPTS_SRC_DIR" ]; then
  for script in "$SCRIPTS_SRC_DIR/"*.sh; do
    [ -f "$script" ] || continue
    filename="$(basename "$script")"
    dest="$CLAUDE_DIR/$filename"
    if [ ! -f "$dest" ] || [ "$FORCE" = true ]; then
      cp "$script" "$dest"
      chmod +x "$dest"
      echo "  Installed scripts/$filename"
      SCRIPT_INSTALLED=$((SCRIPT_INSTALLED + 1))
    else
      echo "  Skipped scripts/$filename (already exists)"
      SCRIPT_SKIPPED=$((SCRIPT_SKIPPED + 1))
    fi
  done
fi

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo ""
echo "Done. $RULE_INSTALLED rule(s) installed, $RULE_SKIPPED skipped."
echo "      $SKILL_INSTALLED skill(s) installed, $SKILL_SKIPPED skipped."
echo "      $CMD_INSTALLED command(s) installed, $CMD_SKIPPED skipped."
echo "      $SCRIPT_INSTALLED script(s) installed, $SCRIPT_SKIPPED skipped."
