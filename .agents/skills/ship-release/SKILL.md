---
name: ship-release
description: >-
  Ships a Studiofront macOS release end-to-end: draft GitHub release notes
  and a CHANGELOG entry for review, bump version, Release build, sign and
  notarize the DMG, generate the Sparkle appcast, archive the dSYM, then
  tag and publish on GitHub. Use when the user asks to release, ship, cut a
  version, or write a changelog for the Studiofront macOS app.
---

# Ship Studiofront Release

Full release pipeline for the Studiofront macOS menu bar app. **Hard gate:** draft notes, CHANGELOG entry, and version for the user to approve before any bump, build, tag, or GitHub publish.

For exact command blocks and paths, see [reference.md](reference.md).

## Checklist

Copy and track:

```
Release progress:
- [ ] 1. Gather commits + current version
- [ ] 2. Draft notes + CHANGELOG entry + proposed version (STOP for approval)
- [ ] 3. Bump version files + xcodegen
- [ ] 4. Release build → sign/notarize DMG → generate appcast → archive dSYM
- [ ] 5. Commit, push, tag, gh release (DMG + appcast + dSYM)
- [ ] 6. Verify GitHub release assets + Sparkle feed
```

## Step 1: Gather

From the repo root:

1. Latest tag: `git describe --tags --abbrev=0`
2. Commits since tag: `git log <tag>..HEAD --pretty=format:'%h %s%n%b'`
3. Diff summary: `git diff <tag>..HEAD --stat`
4. Current version from **both** places in `app/project.yml` (they must match):
   - `targets.Studiofront.info.properties` → `CFBundleShortVersionString`, `CFBundleVersion`
   - `targets.Studiofront.settings.base` → `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`
5. Current top entry in `CHANGELOG.md` (`## [x.y.z] - <date>`)

If the two `project.yml` version pairs don't match, stop and fix before continuing.

## Step 2: Draft notes + CHANGELOG entry (STOP)

Default version bump: patch on the third number (`0.0.N` → `0.0.N+1`, build `N+1`) unless the user named a version.

### Release notes

Draft GitHub release notes in this shape only, user-facing bullets from the actual diff. Do not invent items.

```markdown
## What's new

- **Feature**: short description
…

Sparkle auto-update from X.Y.Z should offer this build.
```

### CHANGELOG entry

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Draft a matching entry, same bullet content as the release notes body (no lead-in bold/description split needed, plain bullets):

```markdown
## [X.Y.Z] - <YYYY-MM-DD>

- Short description of feature or fix
…
```

Insert it above the current top entry.

Present to the user:

- Proposed tag (`vX.Y.Z`) and build number
- Full draft release notes body
- Draft CHANGELOG.md entry
- Brief list of commits included

**Do not bump, build, tag, push, or create a GitHub release until the user explicitly approves** (and any edits they make to the notes or CHANGELOG entry).

## Step 3: Bump (after approval)

1. Set `CFBundleShortVersionString` / `CFBundleVersion` **and** `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `app/project.yml` (four keys, two places, see Step 1).
2. Run `cd app && xcodegen generate`. This regenerates `app/Studiofront/Resources/Info.plist` from the new `project.yml` values. Verify the regenerated file shows the new version.
3. Apply the approved CHANGELOG.md entry.
4. Commit message style: `Ship Studiofront vX.Y.Z.` with one short body sentence on why (include the bump). Include the CHANGELOG.md edit in this commit; do not commit unrelated dirty files.

## Step 4: Build, sign/notarize, appcast, dSYM

1. Release build (see [reference.md](reference.md)).
2. Verify the built app's `Info.plist` shows the new version/build.
3. `./scripts/release-dmg.sh app/build/Build/Products/Release/Studiofront.app`: signs (including nested Sparkle bits), thins embedded frameworks to arm64, strips non-English Sparkle locales, packages `dist/Studiofront.dmg`, notarizes with the `studiofront-notary` keychain profile, and staples.
4. Locate `generate_appcast` under `app/build/SourcePackages/artifacts/sparkle/`, stage `dist/Studiofront.dmg` into `dist/appcast-staging/`, run it, copy `appcast.xml` to `dist/appcast.xml`. Confirm `sparkle:shortVersionString` and `sparkle:version` match the release.
5. **Archive the `.dSYM`.** Zip `app/build/Build/Products/Release/Studiofront.app.dSYM` to `dist/Studiofront-X.Y.Z.dSYM.zip` and confirm `dwarfdump --uuid` matches the shipped binary. The Release config strips the binary (`DEPLOYMENT_POSTPROCESSING = YES` in `app/Config/Release.xcconfig`), so this is the only thing that can symbolicate a crash report from this build, and it otherwise lives only in gitignored derived data.

Sanity-check the artifacts before publishing: the DMG mounts, `lipo -archs` on the app binary and `Sparkle.framework` both report `arm64`, and Sparkle Resources contain only `en.lproj` (non-English locales stripped).

## Step 5: GitHub release

Repo: `nuotsu/studiofront`

1. `git push -u origin HEAD`
2. Annotated tag `vX.Y.Z`, push the tag
3. `gh release create vX.Y.Z dist/Studiofront.dmg dist/appcast.xml dist/Studiofront-X.Y.Z.dSYM.zip --title "Studiofront vX.Y.Z" --notes "…"` using the **approved** notes
4. Verify assets: `gh release view vX.Y.Z --json assets --jq '.assets[].name'` must list `Studiofront.dmg` (and must not list a versioned DMG)

**Hard rule, DMG filename:** upload as **`Studiofront.dmg`** only, never `Studiofront-X.Y.Z.dmg` or any other name. Sparkle (`SUFeedURL` in `app/project.yml`) and the site download (`web/src/lib/download-macos.ts` → `MACOS_DMG_URL`) both depend on the stable `…/releases/latest/download/Studiofront.dmg` URL. Only the dSYM zip is versioned (`Studiofront-X.Y.Z.dSYM.zip`).

All three assets ship every release. Never force-push tags. Never `--no-verify`.

## Step 6: Verify

- `gh release view vX.Y.Z --json assets --jq '.assets[].name'` lists exactly `Studiofront.dmg`, `appcast.xml`, `Studiofront-X.Y.Z.dSYM.zip`
- Confirm the appcast's `sparkle:shortVersionString` / `sparkle:version` match `vX.Y.Z`
- `curl -sS https://github.com/nuotsu/studiofront/releases/latest/download/Studiofront.dmg -o /dev/null -w '%{http_code}\n'` returns `200`
- From a previous build, confirm Sparkle detects and installs the new version

## Local app rules

If opening a local build after ship:

1. `pkill -x Studiofront` first
2. `open` the app only. Do **not** send Cmd+, or auto-open Settings

## Out of scope

- Changing Sparkle keys, signing identity, or notary credentials
- README rewrites (unless the user asks)
- Force-push / history rewrite
- Any website/Sanity version sync: Studiofront's marketing site has no live version string or docs page today
