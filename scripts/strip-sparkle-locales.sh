#!/usr/bin/env bash
# Keep English-only Sparkle localization resources.
#
# Studiofront's UI is English-only, and Sparkle ships ~40 languages across the
# framework, Updater.app, and nested XPCs. Stripping non-English .lproj folders
# before codesign saves a few hundred KB in the Release app / DMG.
#
# Run AFTER building and BEFORE signing. Deleting resources does not rewrite
# Mach-O slices, but release-dmg.sh signs inside-out afterward either way.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") path/to/Studiofront.app

Deletes every *.lproj under Sparkle.framework except en.lproj
(and Base.lproj if present).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "error: path to Studiofront.app is required" >&2
  echo >&2
  usage >&2
  exit 1
fi

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/Contents/Info.plist" ]]; then
  echo "error: not a valid app bundle: $APP_PATH" >&2
  exit 1
fi

SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE" ]]; then
  echo "No Sparkle.framework, nothing to strip."
  exit 0
fi

before="$(du -sk "$SPARKLE" | cut -f1)"
removed=0

while IFS= read -r -d '' lproj; do
  name="$(basename "$lproj")"
  case "$name" in
    en.lproj|Base.lproj) continue ;;
  esac
  rm -rf "$lproj"
  removed=$((removed + 1))
done < <(find "$SPARKLE" -type d -name '*.lproj' -print0)

after="$(du -sk "$SPARKLE" | cut -f1)"
echo "Removed $removed Sparkle locale(s). Framework ${before}K -> ${after}K"
