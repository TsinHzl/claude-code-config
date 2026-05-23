#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
RULES_DIR="$CLAUDE_DIR/rules"
FORCE=false

# Parse flags
for arg in "$@"; do
  case $arg in
    --force) FORCE=true ;;
  esac
done

echo "Installing claude-code-config..."

# Ensure ~/.claude/rules/ exists
mkdir -p "$RULES_DIR"

# Backup existing CLAUDE.md
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  BACKUP="$CLAUDE_DIR/CLAUDE.backup.$(date +%Y%m%d_%H%M%S).md"
  cp "$CLAUDE_DIR/CLAUDE.md" "$BACKUP"
  echo "  Backed up existing CLAUDE.md → $BACKUP"
fi

# Install CLAUDE.md
if [ ! -f "$CLAUDE_DIR/CLAUDE.md" ] || [ "$FORCE" = true ]; then
  cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "  Installed CLAUDE.md"
else
  echo "  Skipped CLAUDE.md (already exists, use --force to overwrite)"
fi

# Install rules
INSTALLED=0
SKIPPED=0
for rule in "$REPO_DIR/rules/"*.md; do
  filename="$(basename "$rule")"
  dest="$RULES_DIR/$filename"
  if [ ! -f "$dest" ] || [ "$FORCE" = true ]; then
    cp "$rule" "$dest"
    echo "  Installed rules/$filename"
    INSTALLED=$((INSTALLED + 1))
  else
    echo "  Skipped rules/$filename (already exists)"
    SKIPPED=$((SKIPPED + 1))
  fi
done

echo ""
echo "Done. $INSTALLED rule(s) installed, $SKIPPED skipped."
echo ""
echo "Next step: edit ~/.claude/CLAUDE.md and fill in your Developer Profile."
