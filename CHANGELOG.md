# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.0.7] - 2026-08-19

- Add document search to the popover, with matches split into dedicated rows and a configurable Open Document shortcut (default ⌘↩)
- Make project name and favicon clicks open Studio, and document rows open the matched document
- Improve popover performance on large Sanity accounts (memoized list derivation, tiered document search, capped presence fan-out, parallel ETag-based refresh)
- Restore native Liquid Glass Settings sidebar and keep it always visible
- Use a single progressive blur at the top of the Liquid Glass project list, with sticky org headers in front of it and more top breathing room

## [0.0.6] - 2026-08-17

- Add Studio URL preference to choose external vs. Sanity-hosted Studio, with a dropdown for projects with multiple registered Studio apps
- Add collaborator name tooltips on hover in the avatar stack
- Redesign the Settings window with a floating sidebar and inset traffic lights, replacing the split-view sidebar
- Add a "Hide scrollbar" preference
- Replace the Manage button's gearshape icon with a custom Sanity-style icon
- Fix avatar tooltip clipping under a pinned section header

## [0.0.5] - 2026-08-17

- Fix Settings window opening more than once

## [0.0.4] - 2026-08-17

- Scope starred projects and pinned orgs to the signed-in Sanity account, fixing favorites leaking between accounts that share a project id
- Fix star icon not updating to gold when toggling a favorite
- Fix Personal Token guidance to point to the correct docs anchor and explain sanity login / sanity debug --secrets
- Fix Settings sidebar toggle not doing anything
- Rename "Presence" setting to "Editor Avatars" with clearer option captions

## [0.0.3] - 2026-08-13

- Add configurable ⌘/ shortcut to cycle Group by
- Enable Show in Dock by default for new installations
- Fix perf/correctness bugs: O(n²) row rendering, blocking disk I/O, stale-refresh race, favicon negative-cache bug, leaked presence continuations

## [0.0.2] - 2026-08-11

- Add Launch at Login toggle
- Add About settings pane with version, links, and Check for Updates
- Make the favorite-toggle keyboard shortcut configurable
- Show favorite jump legends and fix a jump-ordering bug that could select the wrong project
- Give the DMG installer a real app icon and drag-to-Applications arrow

## [0.0.1] - 2026-08-10

Initial release.

- Menu bar popover for switching between Sanity Studios across client organizations
- Account settings with Sanity CLI token detection and manual token entry fallback
- Live presence indicators for other editors active in a project, with the ability to jump to the document they're viewing
- Liquid Glass appearance, with light/dark and settings polish
- Sparkle-based auto-update support
