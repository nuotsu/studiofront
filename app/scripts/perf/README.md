# Popover performance: findings, tools, next steps

Written 2026-11-09 at the end of the v0.3 performance pass, as a handoff.

## How to measure

The app has a scripted benchmark, compiled only with the `BENCHMARK` flag (`Studiofront/App/PerformanceBenchmark.swift`). It hosts the real popover view off-screen, drives the store through typing, arrow keys, scrolling, grouping, presence and refresh, and prints main-thread milliseconds per step.

The scripts here were written for a session scratch folder. Before using them, change the `SCRATCH` path at the top of each `.sh` to any writable folder.

- `bench.sh <label>`: Release build, runs on the cached account and on 300 generated projects, writes `bench-<label>-cache.txt` and `-synthetic.txt`.
- `compare.py <before.txt> <after.txt>`: side-by-side totals per step.
- `exp.sh [nobuild] <flags>...` plus `summarize.py`: one summary line per run (store, layout, display split for 18 keystrokes). Flags are passed as `--perf=a,b`. Only `nodisplay` is still wired up; see "Experiment switches" below.
- `profile.sh <label>`: optimized Debug-signed build (so `sample` can attach), samples the run. `analyze_sample.py <sample.txt> --under "NSHostingView.layout()" <filters>` ranks symbols by inclusive samples.
- `snap.sh <label>`: runs with `--snapshots` and decodes PNGs of the off-screen view (browse, search, date), for checking that a layout change looks the same. It also printed row sizes while that hook existed.

Always measure in Release. Debug builds are several times slower in app code and are not representative.

## Numbers (Release, real account, 44 projects)

Total main-thread time per step, before and after this pass:

| Step | Before | After |
| --- | --- | --- |
| First keystroke of a search | 124 ms | about 75 ms |
| Second keystroke | 80 ms | about 42 ms |
| Back to an empty query | 94 to 106 ms | about 60 ms |
| Scroll back to top | 152 ms | 30 to 50 ms |
| Refresh that changed nothing | 16 ms | 0.5 ms |
| First render (mount) | 272 ms | 100 to 160 ms |
| 18 keystrokes in total | about 1,160 ms | about 720 ms |

On top of this, the search field now applies its text to the list after a 90 ms pause (`StudioStore.queryInput` / `flushQueryInput()`), so fast typing redraws the list once instead of once per character. That is not reflected in the table (the benchmark sets the applied query directly).

## What the profile showed

1. Store filtering is about 1 ms per keystroke. It is not a bottleneck.
2. Almost all time is SwiftUI layout: creating views and laying them out.
3. `ViewThatFits` around the document pills was about 25% of all layout time. Replaced with measured text widths (`PillMetrics`).
4. Every `Button` carries about eight wrapper modifiers. Small row controls now use `onTapGesture`.
5. Row height measuring was not the cost (fixed heights via `FixedHeightRow` did not move the numbers, though they are kept as a safeguard).
6. With row contents stripped to almost nothing, typing still cost about 500 of 720 ms. So after this pass, row contents are roughly a third of the cost and the list structure is the rest. In the profile the structural time sits in `ForEachState.forEachItem`, `_LazyLayout_Subviews.apply`, `DynamicViewList` and `DynamicContainerInfo.updateItems`: the lazy stack walking nested `ForEach`es and the conditional (`if`) views inside each `Section`.
7. Section headers cost about 13% (tested by swapping them for plain text). The scroll-position preference and pinned headers cost little.
8. The sidebar costs up to about 11 ms per keystroke while searching, because its entries mirror the search groups and are rebuilt each time.

## What was changed

- Store: byte-wise search matching, cached row index, cached pinned-org set and org order, `replaceRows` skips identical data, `ProjectActivity.displayDocuments` is stored not recomputed.
- Rows (`ProjectRowChrome.swift`, `ProjectRowView.swift`, `DocumentRowView.swift`): no state or store reads in the row body; hover, selection, copy feedback, favicon and the shortcut legend each live in a small child view; favicons read the cache synchronously; context menu is a lazily evaluated view.
- List (`PopoverRootView.swift`): selection scrolling and section headers moved into their own views so the list body only depends on the list contents; fixed row heights.
- Sidebar: footer and row highlight isolated so spinner and scroll changes redraw less.
- Favicons are decoded and downscaled off the main thread.
- `NativeMenuButton` no longer embeds an AppKit view per button.

## Next steps, in order of expected value

1. Make each `Section`'s content static. In `ProjectList.body` the section content has three `if`s (glass top gap, hidden-projects dropdown, trailing gap plus jump anchor) and a leading `if let first`. Fold them so a section is one `ForEach` plus fixed views: emit the trailing gap and anchor for every section (drop `listPadding.bottom` by the same 8pt), make the hidden dropdown an extra item in the `ForEach`, and move the glass gap into the first row's top padding. Measure with `exp.sh`.
2. Keep the sidebar stable while searching (show the browse entries, or debounce its update), or make `OrganizationPreview` cheaper. This is partly a product decision.
3. Slim the pills further: one `Text` with styled runs per pill instead of an `HStack` of dot plus two texts, and `Capsule().fill().strokeBorder()` as a single background. Check with `snap.sh`.
4. Drop `.help` and duplicate accessibility modifiers where they add little (pin, favicon). Each is one more node per row.
5. Pre-render the popover once after the cache loads so the first open does not pay the mount cost. Untested.

## Experiment switches

To measure what a piece costs, the quickest method was temporary `#if BENCHMARK` branches in the views that swap a piece for a placeholder when `PerformanceBenchmark.flag("name")` is set, then `exp.sh none name`. Those branches were removed from the views at the end of the pass; `flag(_:)` is still in `PerformanceBenchmark.swift`. Re-add branches as needed and strip them before finishing.

## Things to keep in mind

- `ProjectRowView.height` and `DocumentRowView.height` are constants the list relies on. If a row's layout changes, update them (`snap.sh` can confirm).
- `PillMetrics` assumes the pill fonts are system 10.5 and 10 (the theme's `meta` and `timestamp`). If those tokens change, update it.
- Anything that acts on the list from the keyboard must call `store.flushQueryInput()` first (see `AppDelegate.handlePopoverKey`).
- Small row controls no longer dim while pressed, because they are tap gestures and not buttons.
