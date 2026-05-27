#!/usr/bin/env bash
# Uninstaller for cc-usage-statusline.
# Removes the statusLine entry (only if it points at our script) and deletes the script.

set -euo pipefail

DEST="$HOME/.claude/scripts/cc-usage-statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found." >&2
  exit 1
fi

if [[ -f "$SETTINGS" ]]; then
  BACKUP="$SETTINGS.bak-$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
  tmp=$(mktemp)
  jq 'if ((.statusLine.command // "") | endswith("cc-usage-statusline.sh"))
      then del(.statusLine) else . end' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "✓ Removed statusLine from $SETTINGS (backup: $BACKUP)"
fi

if [[ -f "$DEST" ]]; then
  rm -f "$DEST"
  echo "✓ Removed $DEST"
fi

echo
echo "Done. Restart Claude Code to apply."
