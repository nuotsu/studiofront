# Releasing

Studiofront ships as a notarized, Developer ID–signed `.app` distributed via GitHub Releases, with Sparkle checking `releases/latest/download/appcast.xml` for updates (see `SUFeedURL` in `app/project.yml`). There is no CI automation for this yet — every step below is manual.

The marketing site links to a **stable** download URL that must stay unversioned:

`https://github.com/nuotsu/studiofront/releases/latest/download/Studiofront.dmg`

Always publish the DMG as `Studiofront.dmg` (never `Studiofront-<version>.dmg`).

## 1. Bump the version (if needed)

In `app/project.yml`, under the `Studiofront` target:

- `CFBundleShortVersionString` / `MARKETING_VERSION` — the marketing version (e.g. `0.0.1`)
- `CFBundleVersion` / `CURRENT_PROJECT_VERSION` — monotonically increasing build number

Then regenerate the Xcode project:

```sh
cd app
xcodegen generate
```

## 2. Archive

Using the `Studiofront` scheme, Release configuration (manual Developer ID signing is already set up via `app/Config/Release.xcconfig` + your local `Signing.local.xcconfig`):

```sh
xcodebuild archive \
  -project app/Studiofront.xcodeproj \
  -scheme Studiofront \
  -configuration Release \
  -archivePath build/Studiofront.xcarchive
```

Export the signed `.app` from the archive (via Xcode's Organizer, or `xcodebuild -exportArchive` with an `ExportOptions.plist`), then package it as `Studiofront.dmg` for distribution.

## 3. Notarize

```sh
xcrun notarytool submit Studiofront.dmg \
  --apple-id <your-apple-id> \
  --team-id <your-team-id> \
  --keychain-profile <profile> \
  --wait

xcrun stapler staple Studiofront.app
```

Re-package as `Studiofront.dmg` after stapling.

## 4. Generate the appcast

Sparkle's EdDSA public key is already embedded in `app/project.yml` (`SUPublicEDKey`), so the matching private key must already exist in your Keychain from prior setup. Put the packaged `Studiofront.dmg` in a release-artifacts directory, then run Sparkle's `generate_appcast` tool (built as part of the Sparkle package, or downloaded from a [Sparkle release](https://github.com/sparkle-project/Sparkle/releases)):

```sh
# Artifact must be named Studiofront.dmg so the enclosure URL stays unversioned
generate_appcast /path/to/release-artifacts/
```

This produces `appcast.xml` signed with the existing key. The enclosure URL should be:

`https://github.com/nuotsu/studiofront/releases/latest/download/Studiofront.dmg`

## 5. Publish the GitHub Release

```sh
git tag v0.0.1
git push origin v0.0.1

gh release create v0.0.1 \
  Studiofront.dmg \
  appcast.xml \
  --title "v0.0.1" \
  --notes-file <(sed -n '/## \[0.0.1\]/,/## \[/p' CHANGELOG.md)
```

Sparkle expects the appcast at `releases/latest/download/appcast.xml`, which `gh release create` satisfies automatically for the latest release.

## 6. Verify

- Confirm `https://github.com/nuotsu/studiofront/releases/latest/download/Studiofront.dmg` downloads successfully
- Open the downloaded DMG and confirm the app launches without a Gatekeeper warning
- From a previous build, confirm Sparkle detects and installs the new version
