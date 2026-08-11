# Ship Studiofront Release: Reference

Command cookbook and constants. Read from [SKILL.md](SKILL.md) only when executing a step.

## Version sources

| File | Keys |
|------|------|
| `app/project.yml` → `targets.Studiofront.info.properties` | `CFBundleShortVersionString`, `CFBundleVersion` |
| `app/project.yml` → `targets.Studiofront.settings.base` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` |

Both pairs must carry the same values. `xcodegen generate` regenerates `app/Studiofront/Resources/Info.plist` from these; there is no separately hand-edited Info.plist source of truth.

GitHub remote / releases: `nuotsu/studiofront`
Sparkle feed (`SUFeedURL` in `app/project.yml`): `…/releases/latest/download/appcast.xml`
Notary keychain profile: `studiofront-notary` (already created; has prior submission history)

**Asset naming contract:** DMG is always `Studiofront.dmg` (never versioned). Site + Sparkle use `…/releases/latest/download/Studiofront.dmg` (`web/src/lib/download-macos.ts`). Only the dSYM zip includes the version: `Studiofront-X.Y.Z.dSYM.zip`.

## Gather

```bash
git describe --tags --abbrev=0
PREV=$(git describe --tags --abbrev=0)
git log "$PREV"..HEAD --pretty=format:'%h %s%n%b'
git diff "$PREV"..HEAD --stat

# Version: both must match
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' app/Studiofront/Resources/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' app/Studiofront/Resources/Info.plist
grep -A1 'CFBundleShortVersionString\|CFBundleVersion\|MARKETING_VERSION\|CURRENT_PROJECT_VERSION' app/project.yml

# Current CHANGELOG top entry
head -n 15 CHANGELOG.md
```

## Bump + generate

Edit both `info.properties` and `settings.base` version pairs in `app/project.yml`, then:

```bash
cd app
xcodegen generate
```

Verify the regenerated Info.plist:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' app/Studiofront/Resources/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' app/Studiofront/Resources/Info.plist
```

## Release build

```bash
xcodebuild \
  -project app/Studiofront.xcodeproj \
  -scheme Studiofront \
  -configuration Release \
  -derivedDataPath app/build \
  -destination 'platform=macOS' \
  build
```

Verify:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  app/build/Build/Products/Release/Studiofront.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  app/build/Build/Products/Release/Studiofront.app/Contents/Info.plist
```

## Sign, notarize, package DMG

Requires Developer ID Application cert + the `studiofront-notary` notarytool keychain profile (or App Store Connect API key env vars, see `scripts/release-dmg.sh`).

```bash
./scripts/release-dmg.sh app/build/Build/Products/Release/Studiofront.app
```

Output: `dist/Studiofront.dmg`

## Sparkle appcast

```bash
GENERATE_APPCAST=$(find app/build -name generate_appcast -type f | head -1)
mkdir -p dist/appcast-staging
rm -rf dist/appcast-staging/*
cp dist/Studiofront.dmg dist/appcast-staging/
"$GENERATE_APPCAST" dist/appcast-staging
cp dist/appcast-staging/appcast.xml dist/appcast.xml
cat dist/appcast.xml
```

Confirm `sparkle:shortVersionString` and `sparkle:version` match the release. Enclosure URL may point at `…/releases/latest/download/Studiofront.dmg` (intentional). `generate_appcast` also emits `sparkle:hardwareRequirements` `arm64` from the thinned bundle, which is expected and keeps Sparkle from offering the build to Intel Macs.

## Archive the dSYM

The Release binary ships stripped, so the `.dSYM` is the only way to symbolicate a crash report from a released build. Derived data is gitignored, so it must leave the machine as a release asset.

```bash
VER=X.Y.Z
ditto -c -k --keepParent \
  app/build/Build/Products/Release/Studiofront.app.dSYM \
  "dist/Studiofront-$VER.dSYM.zip"

# UUIDs must match
dwarfdump --uuid app/build/Build/Products/Release/Studiofront.app.dSYM
dwarfdump --uuid app/build/Build/Products/Release/Studiofront.app/Contents/MacOS/Studiofront
```

## Artifact sanity checks

```bash
ls -lh dist/Studiofront.dmg
lipo -archs app/build/Build/Products/Release/Studiofront.app/Contents/MacOS/Studiofront   # arm64
# English-only Sparkle (strip-sparkle-locales.sh runs from release-dmg.sh)
find app/build/Build/Products/Release/Studiofront.app/Contents/Frameworks/Sparkle.framework \
  -type d -name '*.lproj' | grep -v '/en.lproj$' | grep -v '/Base.lproj$' && echo 'FAIL: non-English Sparkle locales' || echo 'OK: Sparkle locales English-only'

MP=$(hdiutil attach dist/Studiofront.dmg -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)
lipo -archs "$MP/Studiofront.app/Contents/MacOS/Studiofront"
find "$MP/Studiofront.app/Contents/Frameworks" -name Sparkle -type f -exec lipo -archs {} \;
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MP/Studiofront.app/Contents/Info.plist"
hdiutil detach "$MP" -quiet
```

## Commit, tag, release

```bash
git add app/project.yml app/Studiofront/Resources/Info.plist CHANGELOG.md
# plus any other files intentionally included in this ship commit
git commit -m "$(cat <<'EOF'
Ship Studiofront vX.Y.Z.

Short why / what landed in this cut.
EOF
)"

git push -u origin HEAD
git tag -a vX.Y.Z -m "Studiofront vX.Y.Z"
git push origin vX.Y.Z

gh release create vX.Y.Z \
  dist/Studiofront.dmg \
  dist/appcast.xml \
  dist/Studiofront-X.Y.Z.dSYM.zip \
  --title "Studiofront vX.Y.Z" \
  --notes "$(cat <<'EOF'
## What's new

- **Feature**: description

Sparkle auto-update from PREV should offer this build.
EOF
)"

# Must list Studiofront.dmg (never Studiofront-X.Y.Z.dmg)
gh release view vX.Y.Z --json assets --jq '.assets[].name'
```

## Live checks

```bash
curl -sS 'https://github.com/nuotsu/studiofront/releases/latest/download/Studiofront.dmg' -o /dev/null -w '%{http_code}\n'
gh release view vX.Y.Z --json assets --jq '.assets[].name'
```

## Local open after ship

```bash
pkill -x Studiofront 2>/dev/null || true
sleep 0.2
open app/build/Build/Products/Release/Studiofront.app
```

Do not send Cmd+, or otherwise open Settings.
