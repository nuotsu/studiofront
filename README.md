# Studiofront

A native macOS menu bar app for agency developers and editors who manage many Sanity Studios across multiple client organizations. It's a fast switcher, not a management console: open it, find the right client Studio, jump there.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (arm64) — no Intel/Rosetta support

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen)
2. Copy `app/Config/Signing.local.xcconfig.example` to `app/Config/Signing.local.xcconfig` and fill in your Apple `DEVELOPMENT_TEAM` ID (find it at [developer.apple.com/account](https://developer.apple.com/account) → Membership details). This file is gitignored.
3. From `app/`, run:

   ```sh
   xcodegen generate
   ```

4. Open `app/Studiofront.xcodeproj` in Xcode, select the `Studiofront` scheme, and run.

On first launch, Studiofront looks for a Sanity CLI auth token at `~/.config/sanity/config.json`. If the sandbox can't read it, Settings offers a fallback to grant access or paste a token directly. Tokens are stored in the Keychain only.

## Architecture

Studiofront is one app target plus four local Swift packages:

```
Studiofront/     app target — shell, popover, settings window
Packages/
  SanityKit/     Management API client, models, token storage
  PresenceKit/   PresenceProvider protocol + implementations
  ThemeKit/      theme protocol, token sets, styled primitives
  StudioStore/   persistence, curation state, merge logic
```

See [`studiofront-spec.md`](./studiofront-spec.md) for the full build spec.

## Releasing

See [`RELEASING.md`](./RELEASING.md).

## License

[MIT](./LICENSE)
