#!/usr/bin/env bash
# Package, notarize, and staple a Developer ID–signed Studiofront DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/app/Studiofront/Resources/Studiofront.entitlements"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
OUT_DMG="${OUT_DMG:-$OUT_DIR/Studiofront.dmg}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [path/to/Studiofront.app]

Verifies (or applies) Developer ID signing, builds dist/Studiofront.dmg,
submits it to Apple notarization, staples the ticket, and runs spctl.

Prerequisites:
  1. Active Apple Developer Program membership
  2. Developer ID Application certificate installed in Keychain
  3. app/Config/Signing.local.xcconfig with DEVELOPMENT_TEAM (from example)
  4. Notary credentials, one of:
       - Keychain profile:  xcrun notarytool store-credentials studiofront-notary
         then: NOTARY_PROFILE=studiofront-notary (default)
       - App Store Connect API key:
         NOTARY_KEY_PATH=/path/to/AuthKey_XXXXX.p8
         NOTARY_KEY_ID=XXXXX
         NOTARY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

Environment:
  OUT_DIR            Output directory (default: dist/)
  OUT_DMG            Full output path (default: \$OUT_DIR/Studiofront.dmg)
  CODESIGN_IDENTITY  Codesign identity (default: first "Developer ID Application")
  NOTARY_PROFILE     notarytool keychain profile (default: studiofront-notary)
  SKIP_NOTARIZE=1    Only sign + package DMG (skip notary/staple/spctl)
EOF
}

die() { echo "error: $*" >&2; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  die "path to Studiofront.app is required"$'\n\n'"$(usage)"
fi

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
[[ -d "$APP_PATH" && -f "$APP_PATH/Contents/Info.plist" ]] || die "not a valid app bundle: $APP_PATH"
[[ -f "$ENTITLEMENTS" ]] || die "missing entitlements: $ENTITLEMENTS"

# --- Resolve Developer ID identity -------------------------------------------------
resolve_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "$CODESIGN_IDENTITY"
    return
  fi
  local id
  id="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -1)"
  [[ -n "$id" ]] || die "no Developer ID Application identity found.

Install one via Xcode → Settings → Accounts → Manage Certificates →
Developer ID Application, or create it at developer.apple.com.
Then re-run this script."
  echo "$id"
}

IDENTITY="$(resolve_identity)"
echo "Using identity: $IDENTITY"

# --- Sign nested Sparkle bits, then the app (inside-out) ---------------------------
sign_app() {
  local app="$1"
  local identity="$2"
  local sparkle="$app/Contents/Frameworks/Sparkle.framework"

  echo "Signing $app"

  if [[ -d "$sparkle" ]]; then
    # Sparkle 2.x nested tools / XPCs (paths vary slightly by version)
    local nest
    while IFS= read -r -d '' nest; do
      echo "  codesign $nest"
      codesign --force --options runtime --timestamp --sign "$identity" "$nest"
    done < <(find "$sparkle" \( \
        -name "*.xpc" -o \
        -name "Autoupdate" -o \
        -name "Updater.app" -o \
        -name "Sparkle" \
      \) -print0 2>/dev/null | sort -z)

    echo "  codesign $sparkle"
    codesign --force --options runtime --timestamp --sign "$identity" "$sparkle"
  fi

  # Any other embedded frameworks / dylibs
  local fw
  while IFS= read -r -d '' fw; do
    [[ "$fw" == "$sparkle" ]] && continue
    echo "  codesign $fw"
    codesign --force --options runtime --timestamp --sign "$identity" "$fw"
  done < <(find "$app/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 2>/dev/null)

  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$identity" \
    "$app"
}

# --- Thin embedded frameworks before signing -----------------------------------------
# Sparkle ships universal; this app is arm64-only. Must run before sign_app, since lipo
# rewrites the Mach-O files and invalidates any existing signature.
if [[ -x "$ROOT/scripts/thin-frameworks.sh" ]]; then
  "$ROOT/scripts/thin-frameworks.sh" "$APP_PATH"
fi

# English-only UI: drop Sparkle's non-English .lproj trees before signing.
if [[ -x "$ROOT/scripts/strip-sparkle-locales.sh" ]]; then
  "$ROOT/scripts/strip-sparkle-locales.sh" "$APP_PATH"
fi

sign_app "$APP_PATH" "$IDENTITY"

# --- Verify Developer ID (not ad-hoc) ----------------------------------------------
verify_developer_id() {
  local app="$1"
  local info
  info="$(codesign -dv --verbose=4 "$app" 2>&1)"
  echo "$info" | grep -q "Signature=adhoc" && die "app is still ad-hoc signed after codesign"
  echo "$info" | grep -q "TeamIdentifier=not set" && die "TeamIdentifier not set, check DEVELOPMENT_TEAM / certificate"
  if ! echo "$info" | grep -qi "Authority=Developer ID Application"; then
    # codesign -dv lists Authority lines on stderr already captured
    if ! echo "$info" | grep -qi "Developer ID Application"; then
      die "expected Developer ID Application signature. Got:
$info"
    fi
  fi
  codesign --verify --deep --strict --verbose=2 "$app"
  echo "Signature OK"
  echo "$info" | grep -E '^(Authority|TeamIdentifier|Signature)=' || true
}

verify_developer_id "$APP_PATH"

# --- DMG ---------------------------------------------------------------------------
[[ -x "$ROOT/scripts/create-dmg.sh" ]] || die "missing scripts/create-dmg.sh"
OUT_DIR="$OUT_DIR" OUT_DMG="$OUT_DMG" "$ROOT/scripts/create-dmg.sh" "$APP_PATH"

# Sign the DMG itself (recommended; notarization accepts signed or unsigned DMGs)
echo "Signing DMG $OUT_DMG"
codesign --force --timestamp --sign "$IDENTITY" "$OUT_DMG"

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  echo "SKIP_NOTARIZE=1, skipping notarization. DMG at: $OUT_DMG"
  exit 0
fi

# --- Notarize ----------------------------------------------------------------------
notary_args=()
if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  [[ -f "$NOTARY_KEY_PATH" ]] || die "NOTARY_KEY_PATH not found: $NOTARY_KEY_PATH"
  notary_args=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
  echo "Notarizing with App Store Connect API key $NOTARY_KEY_ID"
else
  PROFILE="${NOTARY_PROFILE:-studiofront-notary}"
  notary_args=(--keychain-profile "$PROFILE")
  echo "Notarizing with keychain profile '$PROFILE'"
  echo "(Create it once: xcrun notarytool store-credentials $PROFILE)"
fi

echo "Submitting $OUT_DMG …"
xcrun notarytool submit "$OUT_DMG" --wait "${notary_args[@]}"

echo "Stapling $OUT_DMG"
xcrun stapler staple "$OUT_DMG"
xcrun stapler validate "$OUT_DMG"

echo "Gatekeeper check"
spctl -a -t open --context context:primary-signature -v "$OUT_DMG"

echo
echo "Ready to upload: $OUT_DMG"
echo "Publish to GitHub Releases (and refresh appcast.xml for Sparkle) as usual."
