# Studiofront — Build Spec

A native macOS menu bar app for agency developers and editors who manage many Sanity Studios across multiple client organizations. It is a fast switcher, not a management console: open it, find the right client Studio, jump there.

Treat this document as the source of truth. Where it says **VERIFY**, run the check before writing implementation code — do not assume.

---

## 1. Targets and constraints

| | |
|---|---|
| Platform | macOS only |
| Minimum OS | macOS 26 (Tahoe) |
| Architecture | Apple Silicon only (arm64). No Intel, no Rosetta target. |
| Language | Swift 6, strict concurrency enabled |
| UI | SwiftUI, with AppKit interop only where SwiftUI cannot reach (see §9) |
| Windows/iOS | Out of scope |

macOS 26 is a hard floor, chosen so Liquid Glass materials are native rather than approximated. Do not add availability fallbacks for older systems, and do not hand-roll blur where a system material exists.

### Performance budget

This is a menu bar utility. It must feel instant and disappear from Activity Monitor when idle.

- Popover visible to first paint of cached content: **under 100ms**. Never show a spinner on open.
- Idle CPU with popover closed: **effectively 0%**. No timers, no polling, no open sockets while closed.
- Idle memory: target under 60MB.
- No network activity while the popover is closed, except one optional background refresh (§6.4).
- Scrolling a 50-project list must hold 120fps on a ProMotion display.

The governing rule: **the popover renders from local cache immediately, then reconciles with the network.** Never block UI on a request.

---

## 2. App shell

- `MenuBarExtra`-based menu bar app, or `NSStatusItem` + `NSPopover` if `MenuBarExtra` proves too limiting for the custom search field and keyboard handling. **VERIFY** which one supports a focused, first-responder `TextField` with full arrow-key interception on macOS 26; pick based on that, not preference.
- `LSUIElement = true` — no Dock icon, no app menu bar.
- Optional "Launch at login" via `SMAppService.mainApp` (§10).
- Optional global hotkey to summon the popover, default unset.
- Popover dismisses on outside click and on `esc`.
- Popover width fixed at roughly 820pt; height grows with content to a max, then scrolls. Match the mockup's proportions.

---

## 3. Module layout

Build as a single app target plus local Swift packages, so the network and presence layers are testable without launching the UI.

```
Studiofront/               app target — shell, popover, settings window
Packages/
  SanityKit/               Management API client, models, token storage
  PresenceKit/             PresenceProvider protocol + implementations
  ThemeKit/                theme protocol, token sets, styled primitives
  StudioStore/             persistence, curation state, merge logic
```

`SanityKit` and `PresenceKit` must not import SwiftUI.

---

## 4. Data model

Two distinct sources that get merged for display. Keep them strictly separate in storage — remote data is a disposable cache, local curation is precious user data and must survive a failed refresh, a token change, or a project disappearing and returning.

### 4.1 Remote (fetched, cacheable, disposable)

```swift
struct SanityProject: Sendable, Identifiable {
    let id: String                  // projectId, e.g. "nw8f3k2a"
    var displayName: String
    var organizationId: String?
    var organizationName: String?
    var studioHost: String?         // -> https://<studioHost>.sanity.studio
    var datasets: [Dataset]
    var members: [Member]
    var currentUserRole: String?
    var createdAt: Date
}

struct Dataset: Sendable, Hashable {
    let name: String
    let aclMode: String             // "public" | "private"
}

struct Member: Sendable, Identifiable {
    let id: String                  // Sanity user id
    var displayName: String
    var imageURL: URL?
    var initials: String            // derived, for avatar fallback
}
```

### 4.2 Local curation (user-owned, never overwritten by a refresh)

```swift
struct ProjectCuration: Sendable, Codable {
    let projectId: String
    var isFavorite: Bool
    var isHidden: Bool
    var manualSortIndex: Int?
    var nickname: String?           // overrides displayName in UI
    var frontendLinks: [NamedLink]  // Sanity does not know these
    var extraStudioLinks: [NamedLink] // localhost, staging, self-hosted
}

struct NamedLink: Sendable, Codable, Hashable, Identifiable {
    let id: UUID
    var label: String               // "Production", "Staging", "localhost:3000"
    var url: URL
}
```

### 4.3 Derived activity (cached, refreshed opportunistically)

```swift
struct ProjectActivity: Sendable {
    var lastDeployedAt: Date?
    var lastEditedDocument: EditedDocument?
    var activeUsers: [Member]       // presence — may be empty
}

struct EditedDocument: Sendable {
    var title: String               // best-effort, see §6.3
    var typeName: String            // drives the small square type badge
    var editedAt: Date
    var deepLinkURL: URL?           // Studio intent link to this doc
}
```

### 4.4 View model

```swift
struct ProjectRow: Sendable, Identifiable {
    var id: String
    var project: SanityProject
    var curation: ProjectCuration
    var activity: ProjectActivity
}
```

Merge in `StudioStore`. A project present in curation but absent from the last remote fetch stays in the store and renders in a dimmed "unavailable" state — it does not vanish. Never delete curation as a side effect of a fetch.

### 4.5 Persistence

Use **SwiftData** for curation and the remote cache, or a single versioned JSON file in Application Support if SwiftData's startup cost measurably breaks the 100ms budget. **Measure before choosing.** Include a schema version field either way.

Do not put tokens in either store — see §5.3.

---

## 5. Authentication

Goal: a developer or editor clicks once, a browser opens, they approve, the app has a token. No pasting for the common case.

Sanity's own CLI does browser-based login, so the flow exists; what is not established is whether Anthropic-external third-party apps can register as a first-class OAuth client against it.

**VERIFY before building §5.1** — check Sanity's current docs for third-party OAuth or app-token flows, and inspect how `sanity login` performs its browser handshake and where it persists the result. Do not build against a guessed endpoint. If no documented third-party flow exists, ship 5.2 + 5.3 as v1 and revisit.

### 5.1 Preferred: browser auth
`ASWebAuthenticationSession` with a custom scheme callback (`studiofront://auth`). Exchange for a token, store in Keychain. Show the authenticated user's name and avatar in Settings once connected.

### 5.2 Zero-setup path for developers
On first launch, look for an existing Sanity CLI credential on disk (**VERIFY** the current location — commonly `~/.config/sanity/config.json`, but confirm rather than trusting this). If found and valid, offer: *"Use your existing Sanity CLI login?"* — one click, no browser.

This will cover most developers on the team instantly. It will not cover editors, which is why 5.1 matters.

### 5.3 Manual fallback
A secure field in Settings for a personal token, with a link to where to create one.

### 5.4 Token handling
- Keychain only, via a small wrapper in `SanityKit`. Never `UserDefaults`, never the SwiftData store, never a plist.
- App Sandbox on, with Keychain access and outgoing network entitlements. Reading a CLI credential from `~/.config` requires either a user-granted file access or a scoped bookmark — resolve how 5.2 coexists with the sandbox, and if it cannot, prompt the user to select the file once and persist a security-scoped bookmark.
- Redact tokens from all logging. No token ever reaches an error message shown in UI.
- Handle 401 by surfacing a single inline "Reconnect" affordance in the popover header, not a modal.

---

## 6. Sanity data layer

All requests through one `SanityClient` actor in `SanityKit`. Typed errors, no throwing of raw `URLError` to callers.

### 6.1 Endpoints
Base: `https://api.sanity.io`, versioned path (`/v2021-06-07/` is the commonly referenced Management API version — **VERIFY** the current recommended version and pin it in one constant).

Needed:
- List projects — drives the whole list, including org association and `studioHost`.
- List datasets per project.
- Project members / ACL — for avatars and the current user's role.

**VERIFY** whether a usage or quota endpoint is publicly available. It is referenced in Sanity's docs as data surfaced on the project's management page, which is not the same as a documented public API. Usage display is **out of scope for v1** and is deliberately not in the UI — do not add it speculatively.

### 6.2 Request discipline
- Fetch the project list once per refresh. Fan out per-project detail calls **only for projects that are visible and not hidden**, with a concurrency cap (`TaskGroup`, max 4–6 in flight).
- Respect `ETag` / conditional requests where the API supports them.
- Every response cached with a timestamp. Cache is authoritative for rendering.
- Cancel all in-flight per-project work when the popover closes.
- Note that polling the Management API consumes the project's API request quota. Do not poll aggressively; this is a real cost to the client's account, not just a performance concern.

### 6.3 Last edited document
Not available from the Management API. Requires a content query against the project's dataset:

```groq
*[!(_id in path("drafts.**"))] | order(_updatedAt desc)[0]{
  _id, _type, _updatedAt, title, name
}
```

Complications to handle:
- Title field names vary by schema. Fall back through `title` → `name` → `_id`.
- A private dataset needs a token with read access to *that project*. A single user token may not grant it across every org. Handle "no access" as a normal, quiet state — show the row without the activity line rather than an error.
- Use the CDN endpoint (`apicdn.sanity.io`) for these reads to avoid burning the 10x-costlier direct API quota.
- Include drafts in a second query if the mockup's "Draft: Atelier Visit" row is meant to reflect drafts — the example implies it is. Query drafts and published, take the most recent, and prefix with "Draft:" when the winner is a draft.

### 6.4 Refresh policy
- On popover open, if cache is older than N minutes (default 5, configurable), refresh in the background while showing cached content.
- Optional, default off: a background refresh on a coarse interval (15+ min) so the list is warm. Must be user-disableable, and must not run on battery below a threshold.
- Manual refresh via `⌘R`.

---

## 7. Presence

Design this so presence is replaceable. It is the least stable part of the system.

```swift
protocol PresenceProvider: Sendable {
    func presence(for projectId: String) -> AsyncStream<[Member]>
    func start(projectIds: [String]) async
    func stopAll() async
}
```

Two implementations behind that protocol:

### 7.1 `RealtimePresenceProvider` (preferred, spike first)
Sanity Studio shows live presence over a websocket transport distinct from the documented `client.listen()` SSE mutation channel. That transport is **not a published, stable public API.**

**Run this spike before committing to it:** open a Sanity Studio in a browser with DevTools on the Network → WS tab, observe the connection Studio opens for presence, and determine (a) the URL shape, (b) whether a standard project or user token authenticates it, (c) the message schema for peers joining and leaving, and (d) whether a listen-only mode exists or whether a client must announce itself to receive others' announcements.

Point (d) is a correctness issue, not just a technical one. If the channel requires announcing, this app would report the user as present in a Studio they have not opened — which is actively wrong data shown to their teammates. **If announcement is mandatory, do not ship this provider.** Fall back to 7.2.

Connection topology, regardless:
- Connect **only** for projects currently rendered in the open popover.
- Tear down every connection on popover close. Zero sockets while closed, no exceptions.
- Cap concurrent connections (6) and stagger connects.
- Any failure degrades silently to 7.2 for that project. Never surface a presence error in the UI.

### 7.2 `ActivityPresenceProvider` (fallback, always works)
Derive "recently active" from documented APIs: query recent mutations and their authors over the last few minutes, map author ids to `Member`, render the same avatar stack. Label it honestly in Settings as recent activity rather than live presence.

### 7.3 UI contract
Both providers feed the identical avatar stack component. Overlapping circular avatars, initials fallback with a deterministic color derived from the user id, max 3 shown plus a `+N`. Empty presence renders nothing — the row does not reserve space or show a placeholder.

---

## 8. Theming

Two complete visual languages, user-switchable at runtime, applying to the entire popover. This is the most likely place for the implementation to sprawl, so constrain it hard.

**Write every view once.** Views must never branch on the active theme. All visual difference flows through injected semantic tokens.

```swift
protocol Theme: Sendable {
    var colors: ColorTokens { get }
    var typography: TypographyTokens { get }
    var metrics: MetricTokens { get }   // radii, spacing scale, row height, border widths
    var surface: SurfaceStyle { get }   // glass material vs. flat card
}
```

Inject via `@Environment`. Build a small set of themed primitives in `ThemeKit` — `RowContainer`, `CopyChip`, `PrimaryButton`, `IconButton`, `SectionHeader`, `AvatarStack`, `TypeBadge` — and compose screens exclusively from those.

### 8.1 Liquid Glass theme
Native macOS 26 materials. Translucent layered chrome, the popover body reading as glass over the desktop. Use the system glass APIs and `NSVisualEffectView` materials where appropriate; do not hand-roll blur or fake translucency with opacity. Respect Reduce Transparency — fall back to a solid surface automatically.

### 8.2 Sanity UI theme
Mirror Sanity Studio's design language: a flat white elevated card on a dark chrome, structured borders, neutral grays, Sanity's blue for primary actions. Do not invent hex values from memory. Extract the real tokens by exporting the HTML bundle from the Claude Design project and reading the computed colors, type scale, and spacing out of the CSS. That export is the color authority for this theme.

### 8.3 Settings window is exempt
The Settings window is a **standard native macOS window with default system styling, always.** It does not participate in theming and must not read the theme environment. Standard `Form`/`TabView` settings layout. This is intentional: settings should look like macOS, not like the app's skin.

### 8.4 Also required
- Light and dark appearance for both themes, following the system by default.
- Full Dynamic Type / accessibility text size support. Rows must not clip at larger sizes.
- VoiceOver labels on every interactive element. The copy chips in particular need spoken labels ("Copy project ID nw8f3k2a").
- Reduce Motion respected on any transition.

---

## 9. Popover UI

Build to the attached mockup. Structure, top to bottom:

**Header**
- Search field, full width, focused automatically on open, placeholder `Search projects, orgs, IDs, datasets, documents…`, `⌘K` hint at the trailing edge.
- Below it: `GROUP BY` segmented control — `Org` | `Last edited`. On the right, a count: `10 of 10 projects` (reflects hidden/filtered state, e.g. `4 of 10`).

**List**
- `FAVORITES` section always first, always present when any favorite exists, regardless of the active grouping.
- Then sections per the active grouping. Grouped by org: section header is the org name with its org id in monospace beside it, dimmed. Grouped by last edited: buckets like `Today` / `This week` / `Earlier`.
- Use `LazyVStack` inside a `ScrollView`. Row identity must be stable across refreshes so scroll position and focus survive a reconcile.

**Row anatomy** (left to right)
1. Favorite star — filled for favorites, outline otherwise, click to toggle.
2. Project avatar, rounded square, letter or initials on a per-project color.
3. Project name (semibold) followed by the project id in a monospace chip.
4. Second line: a small square type badge (`P`, `A`, `N`, `C`, `L`, `G`, `F` — first letter of the document type), the last edited document title, a pencil glyph, and relative time.
5. Right cluster: avatar stack (only if presence non-empty), then icon buttons — globe (open frontend), gear (row settings), then a filled `Studio` primary button.

The mockup shows the dataset chip is not on the collapsed row. Put dataset chips in the row's hover/expanded state or its settings popover, so the default row stays scannable. Both project id and dataset name are click-to-copy with a brief "Copied" confirmation — a subtle inline flash, not a toast.

Rows with no frontend link omit the globe button entirely rather than disabling it.

**Footer**
- Left: keyboard legend — `↑↓ navigate · ↵ open Studio · ⌥↵ open site`.
- Right: `Settings…`

### 9.1 Keyboard
Full keyboard operation is a requirement, not a nicety.

- Typing anywhere filters — search never loses focus to the list.
- `↑` `↓` move selection through visible rows, scrolling to keep selection visible.
- `↵` opens the selected project's primary Studio.
- `⌥↵` opens the primary frontend link.
- `⌘C` copies the selected project id.
- `⌘F` toggles favorite on selection.
- `⌘R` refresh. `⌘,` Settings. `esc` clears search, or dismisses if search is empty.
- Digit keys `1`–`9` with `⌘` jump to the nth favorite.

Arrow keys must not be swallowed by the text field. This is the main reason to consider `NSPopover` over `MenuBarExtra` (§2) — resolve it early with a spike, because retrofitting is painful.

### 9.2 Search
Local, synchronous, over the merged in-memory list. Never a network call. Matches across: project name, nickname, org name, project id, dataset names, last edited document title, and link labels. Case- and diacritic-insensitive substring matching is sufficient — do not add fuzzy ranking in v1. Must stay under one frame for 50 projects.

---

## 10. Settings

Native window, standard styling (§8.3), opened via `Settings…` or `⌘,`. Tabs:

- **General** — theme picker (Liquid Glass / Sanity UI), appearance (System/Light/Dark), launch at login, global hotkey, refresh interval, background refresh toggle.
- **Account** — connected Sanity identity with avatar, sign out, token source indicator (browser / CLI / manual).
- **Projects** — the full list including hidden ones, with show/hide toggles, drag to reorder for manual sort, and per-project editing of nickname, frontend links, and extra Studio links.
- **Advanced** — presence mode (real-time / activity-only / off), cache location, clear cache, diagnostic log export with tokens redacted.

---

## 11. Deep links

- Studio: `https://<studioHost>.sanity.studio` when `studioHost` exists; otherwise fall back to the project's Manage page and let the user add a custom Studio link.
- Deep link to a specific document: Studio intent URL. **VERIFY** the current intent URL format before implementing; if uncertain, link to the Studio root rather than constructing a URL that might 404.
- Manage: the project's page on Sanity's management dashboard.
- Frontend: whatever the user configured. Treat the first link as primary.

Open all links with `NSWorkspace.shared.open`. Validate stored URLs on save — reject anything that is not `http`/`https`.

---

## 12. Build order

Ship in this sequence. Each phase should be independently runnable.

1. **Shell** — menu bar item, popover, hardcoded fixture data, both themes wired through `ThemeKit`. Resolve the keyboard/popover question here (§9.1). No network at all.
2. **Auth** — Keychain, manual token, CLI-credential detection, Settings > Account.
3. **Data** — `SanityClient`, projects + datasets + members, persistence, cache-first rendering, refresh policy.
4. **Curation** — favorites, hide/show, reorder, nicknames, custom links, Settings > Projects.
5. **Activity** — last edited document via CDN queries, last deploy.
6. **Presence** — `ActivityPresenceProvider` first (it always works), then the real-time spike (§7.1) behind the same protocol.
7. **Polish** — accessibility pass, Reduce Transparency/Motion, performance profiling against §1's budget, browser auth if §5.1 verified viable.

---

## 13. Explicitly out of scope for v1

Do not build these, and do not leave stubs for them:
- Plan tier and usage/quota display
- Editing content from the app
- Webhook or CORS management
- Creating projects or datasets
- Windows, iOS, or Intel support
- Fuzzy search ranking
- Notifications of any kind

---

## 14. Verify before writing code

Consolidated list of things not to guess at:

1. Current Management API version string and the exact endpoints for projects, datasets, members.
2. Whether a documented third-party OAuth/app-auth flow exists for Sanity (§5.1).
3. Location and format of the Sanity CLI credential file on macOS (§5.2), and whether reading it is compatible with the App Sandbox.
4. The presence websocket's URL, auth, message schema, and whether listen-only is possible (§7.1) — including the announcement question, which can veto the whole approach.
5. Studio intent URL format for document deep links (§11).
6. Whether `MenuBarExtra` supports the required keyboard and focus behavior on macOS 26, or whether `NSPopover` is necessary (§2, §9.1).
7. Whether any public usage/quota endpoint exists, for a later version only.

Where a check comes back negative, say so and use the stated fallback rather than improvising an undocumented alternative.
