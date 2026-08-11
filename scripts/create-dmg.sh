#!/usr/bin/env bash
# Package a built Studiofront.app into a drag-to-Applications DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKGROUND="$ROOT/packaging/dmg/background.png"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
OUT_DMG="${OUT_DMG:-$OUT_DIR/Studiofront.dmg}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [path/to/Studiofront.app]

Creates a DMG that guides users to drag Studiofront.app into Applications.
Uses packaging/dmg/background.png (a drag arrow + "Drag to install" caption)
when present, and falls back to a plain layout without it otherwise. Either
way, the DMG's own volume icon is set to the app's compiled icon
(Contents/Resources/<CFBundleIconFile>.icns) when one is found, instead of
the generic disk icon.

Environment:
  OUT_DIR   Output directory (default: dist/)
  OUT_DMG   Full output path (default: \$OUT_DIR/Studiofront.dmg)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg is not installed. Install it with:" >&2
  echo "  brew install create-dmg" >&2
  exit 1
fi

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "error: path to Studiofront.app is required" >&2
  echo >&2
  usage >&2
  exit 1
fi

# Resolve and validate .app bundle
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/Contents/Info.plist" ]]; then
  echo "error: not a valid app bundle: $APP_PATH" >&2
  exit 1
fi

# --- Resolve the app's own icon for the DMG's volume icon --------------------------
resolve_volicon() {
  local plist="$APP_PATH/Contents/Info.plist"
  local name
  name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist" 2>/dev/null || true)"
  [[ -z "$name" ]] && name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$plist" 2>/dev/null || true)"
  [[ -z "$name" ]] && return 0

  [[ "$name" != *.icns ]] && name="$name.icns"
  local candidate="$APP_PATH/Contents/Resources/$name"
  [[ -f "$candidate" ]] && echo "$candidate"
}

VOLICON="$(resolve_volicon)"
if [[ -n "$VOLICON" ]]; then
  echo "Using volume icon: $VOLICON"
else
  echo "No app icon found on $APP_PATH, DMG will use the default disk icon."
fi

mkdir -p "$(dirname "$OUT_DMG")"
rm -f "$OUT_DMG"

# Stage a clean folder containing only the app (create-dmg copies folder contents)
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/studiofront-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGE/Studiofront.app"

echo "Packaging $APP_PATH -> $OUT_DMG"

# ULMO (lzma) instead of create-dmg's default UDZO (zlib): noticeably smaller for the
# same content. ULMO needs macOS 10.15+ to mount; the app itself requires 26.0.
#
# Small window sized to fit both icons in one view (no scrolling): Studiofront.app
# (left) at 120,130; Applications (right) at 360,130. packaging/dmg/background.png,
# when present, draws the drag arrow between those same two points.
ARGS=(
  --volname "Studiofront"
  --window-size 480 300
  --icon-size 96
  --icon "Studiofront.app" 120 130
  --hide-extension "Studiofront.app"
  --app-drop-link 360 130
)
[[ -n "$VOLICON" ]] && ARGS+=(--volicon "$VOLICON")

if [[ -f "$BACKGROUND" ]]; then
  ARGS+=(--background "$BACKGROUND")
else
  echo "No background at $BACKGROUND, using a plain layout without the drag arrow."
fi

ARGS+=(--format ULMO)

create-dmg "${ARGS[@]}" "$OUT_DMG" "$STAGE"

echo "Created $OUT_DMG"
