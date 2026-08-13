#!/usr/bin/env bash
# Build the HTML5 export and serve it locally for a quick playtest — in a
# desktop browser, in Chrome's device toolbar (Cmd+Shift+M) to emulate a phone
# with touch, or on a real phone/tablet over the LAN. Ctrl+C stops the server.
#
# The build goes to builds/web/ (gitignored), NOT the docs/ deploy dir, so
# local testing never touches your GitHub Pages build.
#
# Overridable via env: GODOT=/path/to/Godot  PORT=8000
set -euo pipefail

cd "$(dirname "$0")"

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
PORT="${PORT:-8000}"
PRESET="Web"
OUT="builds/web"

if [ ! -x "$GODOT" ]; then
  echo "Godot not found at: $GODOT" >&2
  echo "Set GODOT=/path/to/Godot and re-run." >&2
  exit 1
fi

VERSION="$("$GODOT" --version 2>/dev/null | head -1)"

# Web export needs the matching export templates installed. Fail with a clear
# message instead of a cryptic export error if they're missing.
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates"
if ! ls -d "$TEMPLATE_DIR"/*/ >/dev/null 2>&1; then
  echo "Export templates are not installed (need to match $VERSION)." >&2
  echo "In Godot: Editor -> Manage Export Templates -> Download and Install," >&2
  echo "then re-run this script." >&2
  exit 1
fi

echo "Exporting web build ($PRESET) to $OUT/ ..."
mkdir -p "$OUT"
"$GODOT" --headless --path . --export-debug "$PRESET" "$OUT/index.html"

IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo localhost)"
echo
echo "Serving on:"
echo "  this Mac : http://localhost:$PORT/"
echo "  phone    : http://$IP:$PORT/   (same Wi-Fi network)"
echo "  device sim: open the localhost URL in Chrome, then Cmd+Shift+M"
echo

python3 tools/serve.py "$OUT" "$PORT" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' INT TERM EXIT
sleep 1
open "http://localhost:$PORT/" 2>/dev/null || true
wait "$SERVER_PID"
