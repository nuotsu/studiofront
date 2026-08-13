# Studiofront performance/refactoring audit

Date: 2026-08-13
Scope: `app/` (the macOS Swift app). `web/` was not audited — separate Next.js/Sanity codebase.

This audit read every file it names (not a heuristic scan). File:line references point at the state of the code before this pass's fixes; a few have shifted slightly as a result of the fixes below.

## Fixed in this pass

### 1. `StudioStore` — O(n²) row rendering, duplicate filter passes

- **`favoriteIndex(forRowID:)` was called once per rendered row** (from `ProjectRowView`), and each call recomputed the full filter + sort over all rows (`sortedFavorites` → `visibleRows` → `matches()` per row). Rendering N rows did O(n²) work. Fixed by precomputing a `favoriteIndexByID: [String: Int]` once per list build and threading it down as a parameter (`StudioStore.swift`, `PopoverRootView.swift`, `ProjectRowView.swift`).
- **`ProjectRowView.isFavorite` did `store.rows.first(where:)`** — an O(n) scan per row, and it subscribed every row's view to the *entire* `rows` array under `@Observable`, so a presence update anywhere in the list invalidated every row. Changed to read `row.curation.isFavorite` directly (already available, no store access needed).
- **`groups` computed `visibleRows` twice per access** — once directly, once again inside the (now-private-backed) `sortedFavorites`. Extracted a `sortedFavorites(from:)` helper so `groups` computes the filtered list once and reuses it.
- Also fixed two secondary duplicate-computation spots in `PopoverRootView`: the "gap before next group" check and the empty-state check each independently re-read `store.groups`/`store.visibleRows`; both now reuse the `groups` array already computed once at the top of `list`.

### 2. `PersistenceStore` blocking I/O + `ProjectSyncService` stale-write race + unbounded growth

- **Every favorite/org-favorite toggle triggered a synchronous JSON encode + atomic file write on the main actor** (`persistCuration()` → `PersistenceStore.save()`, called directly from `StudioStore.toggleFavorite`/`toggleOrganizationFavorite`). Moved the actual encode/decode/read/write work into a private serializing `actor IO` nested in `PersistenceStore`, so it now runs off the main actor. `save()` stays a fire-and-forget synchronous call (no caller signature changes) but the disk work itself no longer blocks the UI thread. `load()` is now `async`; its two callers (`ProjectSyncService.loadCache()`/`handleAuthChange()`) were updated accordingly, cascading up to `AppDelegate`'s two call sites.
  - Note: writes are serialized on one actor specifically so two overlapping `save()` calls (e.g. rapid-fire favorite clicks) can't interleave writes to the same file — a risk a naive "just wrap each save in its own detached Task" fix would have introduced.
- **Stale-refresh race**: `performRefresh`'s `generation` guard only protected `isRefreshing`/`inFlight` bookkeeping in the `refresh(force:)` wrapper, not the `applySnapshotToStore()`/`PersistenceStore.save()` calls inside `performRefresh` itself. Because Swift task cancellation is cooperative (only checked at explicit points), a superseded refresh could still finish and overwrite fresher data written by a newer refresh. Added a `generation` parameter to `performRefresh` and a guard immediately before all three call sites that mutate the store/disk (the "not modified" fast path, the normal success path, and the generic `catch`).
- **Unbounded growth**: `snapshot.etags` and `snapshot.activity` accumulated an entry per project ever seen and were never pruned — a permanently growing blob fully re-serialized on every save. Added pruning (keyed off the current `remote` project set) right after the per-project dataset fetch loop in `performRefresh`.
- **Minor**: removed a wasted `orgNames` dictionary build that was unconditionally overwritten on the normal (organizations-fetch-succeeds) path; it's now only built in the fallback branch.

### 3. `FaviconCache` — permanent negative-caching bug + unbounded growth

- The cache was `[String: NSImage?]`; a failed fetch stored `nil`, and the lookup (`if let cached = cache[host]`) matched `.some(nil)` on every subsequent call — one transient network hiccup permanently disabled that project's favicon for the rest of the process lifetime. Switched to `NSCache<NSString, NSImage>`, which only ever stores successful fetches (so failures retry on next access) and gets automatic eviction under memory pressure instead of unbounded dictionary growth.

### 4. `RealtimePresenceProvider` — leaked stream continuations

- `attach(_:for:)` had no `onTermination` handler (unlike its `ActivityPresenceProvider` counterpart) and silently overwrote any existing continuation for a project without finishing it first — the previous consumer's `for await` loop would hang forever. Added a matching `onTermination` → `detach` wire-up in `presence(for:)`, and `attach` now finishes the prior continuation before replacing it.
- `start(projectIds:)`'s removal path cleared `connections`/`sessions`/`fallbackProjectIds` for a dropped project but not `continuations` — leaking an entry per project that drops out of the tracked set without a full `stopAll()`. Now cleared there too.

### 5. `PresenceCoordinator` — dead code

- `willShow()` returned early for `.off` via a `guard`, then had a second, unreachable `case .off: provider = nil` in the switch below it. Replaced with `case .off: break // unreachable: guarded above` so the duplicate nil-assignment is gone and the reason it's unreachable is explicit.

**Build**: `xcodebuild -project Studiofront.xcodeproj -scheme Studiofront -configuration Debug build` succeeds with zero new warnings (the two warnings present are pre-existing and in files this pass didn't touch).

**Not yet manually exercised in the running app** — per your standing preference, I'm not driving/screenshot-testing the GUI myself. Worth checking by hand: search-as-you-type still filters correctly, rapid favorite-toggling doesn't visibly stutter or lose data on relaunch, a refresh triggered mid-flight followed immediately by another doesn't show stale data, and a favicon that fails once (e.g. brief airplane mode) recovers on a later attempt instead of staying blank forever.

## Documented, not implemented (recommended follow-ups)

These are larger, multi-file reshuffles — higher risk, better done as their own reviewed pass rather than bundled into a "top fixes" pass.

### `AppDelegate.swift` (538 lines) — doing 7+ jobs in one class
Status-item lifecycle, native-menu construction, popover lifecycle, global hotkey wiring, appearance/animation forcing across AppKit, activation-policy (dock icon) toggling, dual settings-window management (SwiftUI scene raced against a manually-hosted AppKit fallback via a 0.25s timer guess), and keyboard-event routing (`handlePopoverKey`, a 58-line function mixing three different matching strategies). Recommend splitting into `StatusItemController`, `PopoverController`, `SettingsWindowController`, `PopoverKeyRouter`.

`handlePopoverKey`'s fixed-shortcut table is duplicated in `ShortcutRecorderControl.ReservedShortcut` — the code's own comment (`ShortcutRecorderControl.swift:31-32`) flags this as a manual-sync hazard: *"mirrors the fixed cases hardcoded in `AppDelegate.handlePopoverKey`... update both places together if it ever changes."*

Several `DispatchQueue.main.async`/`asyncAfter` calls sit alongside `Task`/async-await in this already-`@MainActor` class — most are timing-guesses working around AppKit/SwiftUI interop races, each with a comment explaining the specific glitch being dodged (menu rendering truncated on `popUp`, Liquid Glass crossfading on appearance change, Settings scene not reliably materializing for an accessory app). Worth revisiting once the window-management split above happens, since several of these guesses might become unnecessary or at least easier to reason about in isolation.

### `ThemeKit/Primitives.swift` (517 lines) — grab-bag file
At least 9 unrelated categories in one file: row/container chrome, buttons, section headers, presence avatars, badges, search-field chrome, keyboard-glyph rendering, a grouping-menu control, a project avatar view, and a plain string-utility function (`DisplayInitials`) that isn't even a view. Recommend splitting by category (e.g. `Buttons.swift`, `Avatars.swift`, `SearchChrome.swift`, `KeyboardGlyphs.swift`).

### `SettingsRootView.swift` (393 lines) — view + 3 AppKit interop types bundled together
Contains the actual settings-pane-switch/search view alongside two `NSViewRepresentable`s (`SettingsSplitViewTuner`, `SettingsSidebarSearchField`) and an `NSTextField` subclass (`CaretPreservingTextField`) — each a separate, independently-comprehensible AppKit workaround. Recommend extracting the three AppKit interop types into their own file(s), leaving the SwiftUI view logic on its own.

### `AppSettings.swift` — persistence boilerplate, triplicated source of truth
~20 nearly-identical `didSet { UserDefaults.standard.set(_, forKey:) }` blocks, one per property — no functional bug (UserDefaults batches its own disk writes), but 100% mechanical duplication that a small property-wrapper or helper could collapse. Separately, the same ~20 properties are represented three ways by hand (memberwise `init` parameters, the `Keys` string-constant enum, and `load()`'s individual `UserDefaults.object(forKey:)` calls) with nothing enforcing they stay in sync — the same category of risk as the `SettingsSearch` triplication below.

Also inconsistent side-effect wiring: `appearancePreference`'s `didSet` reaches directly into `AppDelegate.shared?.applyAppearance(...)` as a side effect of a property set, while `showInDock` and `menuBarIconPreference` trigger their AppKit side effects from `.onChange` in the view layer instead (`GeneralSettingsView.swift`/`AppearanceSettingsView.swift`) — two different wiring patterns for conceptually the same kind of "setting changed → tell AppKit" need.

`launchAtLogin`'s `SMAppService` registration failure is silently swallowed (only a comment, no logging or user feedback) — low severity but worth a log line at minimum.

### `AppearanceSettingsView.swift` — three near-identical pickers
`MenuBarIconPicker`, `ThemePicker`, `AppearancePicker` are ~90%-identical `HStack` + `ForEach(...allCases)` + tile-wrapper components, differing only in the swatch view injected. Collapsing to one generic picker would remove most of the file.

### `SettingsSearch.swift` — triplicated settings metadata
Every setting's search metadata exists in three places by hand: the `SettingsSearchTarget` enum case, the `.settingsHighlight(_:)` call site in the relevant pane, and a `SettingsSearchIndex` entry (title/keywords/pane/icon) — nothing enforces the three stay in sync when a setting is added or renamed.

### No test target
No unit or UI test target exists anywhere in the project (only the vendored Sparkle dependency has its own tests, irrelevant to this codebase). Given what this audit found, `StudioStore`'s filtering/grouping/favorite logic and `PersistenceStore`'s encode/decode round-trip are the highest-value places to start — they're the most logic-heavy, most bug-prone code in the app, and the fixes in this pass would have been much faster to verify with even a handful of unit tests around `matches()`, `groups`, and `favoriteIndexByID`.

### Minor style notes
- Four force-unwrapped `URL(string:)!` literals in `AboutSettingsView.swift`/`AccountSettingsView.swift` — all static strings, so low real risk, but worth a failable `static let` pattern for consistency.
- Four near-identical fire-and-forget `Task { await auth.xxx() }` button actions in `AccountSettingsView.swift`, each with no shared cancellation/loading-state handling beyond whatever `auth` itself tracks.
