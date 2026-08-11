# Releasing

Studiofront ships as a notarized, Developer ID–signed `.app` distributed via GitHub Releases, with Sparkle checking `releases/latest/download/appcast.xml` for updates (see `SUFeedURL` in `app/project.yml`).

The full pipeline (drafting release notes and a CHANGELOG entry for approval, bumping the version, building, signing/notarizing, generating the appcast, archiving the dSYM, and publishing) is automated by the Claude Code skill at `.agents/skills/ship-release/`. This doc is the human-readable summary; see that skill's `SKILL.md` and `reference.md` for exact commands.

The marketing site links to a **stable** download URL that must stay unversioned:

`https://github.com/nuotsu/studiofront/releases/latest/download/Studiofront.dmg`

Always publish the DMG as `Studiofront.dmg` (never `Studiofront-<version>.dmg`).

## 1. Bump the version

In `app/project.yml`, under the `Studiofront` target, in **both** places:

- `info.properties`: `CFBundleShortVersionString`, `CFBundleVersion`
- `settings.base`: `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`

Then regenerate the Xcode project (this also rewrites `app/Studiofront/Resources/Info.plist`):

```sh
cd app
xcodegen generate
```

Add a matching entry to `CHANGELOG.md` (Keep a Changelog format).

## 2. Release build

```sh
xcodebuild \
  -project app/Studiofront.xcodeproj \
  -scheme Studiofront \
  -configuration Release \
  -derivedDataPath app/build \
  -destination 'platform=macOS' \
  build
```

## 3. Sign, notarize, package the DMG

Developer ID signing is already set up via `app/Config/Release.xcconfig` + your local `Signing.local.xcconfig`. Notarization uses the `studiofront-notary` keychain profile (create it once with `xcrun notarytool store-credentials studiofront-notary`).

```sh
./scripts/release-dmg.sh app/build/Build/Products/Release/Studiofront.app
```

This thins embedded frameworks to arm64, strips non-English Sparkle locales, signs (including nested Sparkle bits), packages `dist/Studiofront.dmg`, notarizes, staples, and runs a Gatekeeper check.

## 4. Generate the appcast

Sparkle's EdDSA public key is already embedded in `app/project.yml` (`SUPublicEDKey`), so the matching private key must already exist in your Keychain from prior setup.

```sh
GENERATE_APPCAST=$(find app/build -name generate_appcast -type f | head -1)
mkdir -p dist/appcast-staging
cp dist/Studiofront.dmg dist/appcast-staging/
"$GENERATE_APPCAST" dist/appcast-staging
cp dist/appcast-staging/appcast.xml dist/appcast.xml
```

## 5. Archive the dSYM

The Release build strips the binary (`DEPLOYMENT_POSTPROCESSING = YES`), so the `.dSYM` is the only way to symbolicate a crash from a shipped build:

```sh
VER=0.0.1
ditto -c -k --keepParent \
  app/build/Build/Products/Release/Studiofront.app.dSYM \
  "dist/Studiofront-$VER.dSYM.zip"
```

## 6. Publish the GitHub Release

```sh
git tag v0.0.1
git push origin v0.0.1

gh release create v0.0.1 \
  dist/Studiofront.dmg \
  dist/appcast.xml \
  dist/Studiofront-0.0.1.dSYM.zip \
  --title "Studiofront v0.0.1" \
  --notes-file <(sed -n '/## \[0.0.1\]/,/## \[/p' CHANGELOG.md)
```

Sparkle expects the appcast at `releases/latest/download/appcast.xml`, which `gh release create` satisfies automatically for the latest release.

## 7. Verify

- Confirm `https://github.com/nuotsu/studiofront/releases/latest/download/Studiofront.dmg` downloads successfully
- Open the downloaded DMG and confirm the app launches without a Gatekeeper warning
- From a previous build, confirm Sparkle detects and installs the new version
