#!/usr/bin/env bash
# Installer for cc-usage-statusline.
# Copies the script into ~/.claude/scripts/ and wires it into ~/.claude/settings.json,
# preserving any existing settings (statusLine is replaced, everything else untouched).

set -euo pipefail

SCRIPT_NAME="cc-usage-statusline.sh"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.claude/scripts"
DEST="$DEST_DIR/$SCRIPT_NAME"
SETTINGS="$HOME/.claude/settings.json"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-1}"   # override with: REFRESH_INTERVAL=5 ./install.sh

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found." >&2
  echo "  macOS:  brew install jq" >&2
  echo "  Debian: sudo apt install jq" >&2
  exit 1
fi

if [[ ! -f "$SRC_DIR/$SCRIPT_NAME" ]]; then
  echo "Error: $SCRIPT_NAME not found next to install.sh" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
cp "$SRC_DIR/$SCRIPT_NAME" "$DEST"
chmod +x "$DEST"
echo "✓ Installed script -> $DEST"

[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"

if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
  echo "Error: $SETTINGS is not valid JSON. Fix it and re-run." >&2
  exit 1
fi

BACKUP="$SETTINGS.bak-$(date +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$BACKUP"
echo "✓ Backed up settings -> $BACKUP"

existing=$(jq -r '.statusLine.command // empty' "$SETTINGS")
if [[ -n "$existing" && "$existing" != "$DEST" ]]; then
  echo "! Replacing an existing statusLine command:"
  echo "    $existing"
  echo "  (restore it from the backup above if you want it back)"
fi

tmp=$(mktemp)
jq --arg cmd "$DEST" --argjson ri "$REFRESH_INTERVAL" \
  '.statusLine = {type: "command", command: $cmd, refreshInterval: $ri}' \
  "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "✓ Wired statusLine into $SETTINGS (refreshInterval=${REFRESH_INTERVAL}s)"

echo
echo "Done. Restart Claude Code (or open a new window) to see the usage statusline."
