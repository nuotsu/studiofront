#!/usr/bin/env bash
# Strip non-arm64 slices from embedded frameworks.
#
# Studiofront is an Apple Silicon-only app (see ARCHS in app/project.yml), but Sparkle
# ships universal, so roughly half of Contents/Frameworks is dead x86_64 weight.
#
# Run this AFTER building and BEFORE signing. lipo rewrites the Mach-O files, which
# invalidates any existing signature. scripts/release-dmg.sh signs the nested Sparkle
# binaries inside-out, so the normal order is:
#
#     thin-frameworks.sh Studiofront.app && release-dmg.sh Studiofront.app
set -euo pipefail

ARCH="${ARCH:-arm64}"

usage() {
  cat <<EOF
Usage: $(basename "$0") path/to/Studiofront.app

Thins every embedded framework Mach-O down to a single architecture.

Environment:
  ARCH   Architecture to keep (default: arm64)
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

FRAMEWORKS="$APP_PATH/Contents/Frameworks"
if [[ ! -d "$FRAMEWORKS" ]]; then
  echo "No Contents/Frameworks, nothing to thin."
  exit 0
fi

before="$(du -sk "$FRAMEWORKS" | cut -f1)"
thinned=0

# Every Mach-O under Frameworks, whatever its name or nesting (Sparkle itself,
# Autoupdate, Updater.app, and the Installer/Downloader XPC services).
while IFS= read -r -d '' file; do
  # Skip symlinks (framework version aliases point at the real files).
  [[ -L "$file" ]] && continue
  file -b "$file" | grep -q "Mach-O" || continue

  archs="$(lipo -archs "$file" 2>/dev/null || true)"
  [[ -z "$archs" ]] && continue
  # Already single-arch, or doesn't contain the arch we want: leave it alone.
  [[ "$archs" == "$ARCH" ]] && continue
  if ! grep -qw "$ARCH" <<<"$archs"; then
    echo "  skip (no $ARCH): ${file#"$APP_PATH"/}  [$archs]"
    continue
  fi

  echo "  thin $ARCH: ${file#"$APP_PATH"/}  [$archs]"
  tmp="$(mktemp)"
  lipo -thin "$ARCH" "$file" -output "$tmp"
  # Preserve the original mode, then replace in place.
  chmod --reference="$file" "$tmp" 2>/dev/null || chmod "$(stat -f "%OLp" "$file")" "$tmp"
  mv -f "$tmp" "$file"
  thinned=$((thinned + 1))
done < <(find "$FRAMEWORKS" -type f -print0)

after="$(du -sk "$FRAMEWORKS" | cut -f1)"
echo "Thinned $thinned binaries to $ARCH. Frameworks ${before}K -> ${after}K"

if [[ "$thinned" -gt 0 ]]; then
  echo "Signatures are now invalid; sign the app (scripts/release-dmg.sh does this)."
fi
