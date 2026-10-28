import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class StudioStore {
    public var rows: [ProjectRow]
    public var organizations: [OrganizationRecord]
    // The list inputs below invalidate the memoized list themselves, so the
    // first render after a change (e.g. a keystroke) already shows the new
    // results instead of one stale frame plus a second render from `.onChange`.
    public var query: String = "" {
        didSet { listInputDidChange(query != oldValue) }
    }
    public var groupBy: GroupBy = .organization {
        didSet { listInputDidChange(groupBy != oldValue) }
    }
    public var selectedID: String?
    public var copiedKey: String?
    public var searchFocusToken: UInt = 0
    public var isRefreshing: Bool = false
    public var hideArchivedProjects: Bool = true {
        didSet { listInputDidChange(hideArchivedProjects != oldValue) }
    }
    public var onCurationChanged: (() -> Void)?
    public var onRefreshRequested: (() -> Void)?
    /// Fired after `replaceRows` — the only point at which the set of
    /// eligible project ids for presence can change while the popover stays
    /// open (no per-row visibility/hide toggle exists yet).
    public var onRowsReplaced: (() -> Void)?
    /// Per-project presence board, session-lived and never persisted. Stored
    /// behind `@ObservationIgnored` so dictionary membership changes do not
    /// invalidate every row; views that need avatars observe
    /// `presenceSlice(for:).members` instead.
    @ObservationIgnored
    private var presenceSlices: [String: PresenceSlice] = [:]
    /// Live, per-project document search results for the current query —
    /// populated by `DocumentSearchCoordinator` as each project's search
    /// resolves. Cleared whenever the query changes or drops below the
    /// coordinator's minimum length. Keyed by project id.
    public var liveDocumentMatchesByProject: [String: [EditedDocument]] = [:]
    /// Project ids with a live document search still in flight for the
    /// current query — drives the header's loading indicator.
    public var searchingProjectIDs: Set<String> = []
    public var isSearchingDocuments: Bool { !searchingProjectIDs.isEmpty }
    /// True after Command has been held for 0.3s — drives the ⌘1–9 avatar overlays.
    public var showFavoriteShortcutLegends: Bool = false

    @ObservationIgnored private var copyResetTask: Task<Void, Never>?
    @ObservationIgnored private var commandHoldRevealTask: Task<Void, Never>?

    private struct ListState {
        var visibleRows: [ProjectRow]
        var groups: [ProjectGroup]
        var flatVisibleIDs: [String]
        /// Recency-sorted favorites: what the Favorites group renders and what ⌘N selects.
        var favorites: [ProjectRow]
        var favoriteIndexByID: [String: Int]
    }

    /// The one observed piece of list memoization: bumping it is what tells
    /// views to re-read `groups`. The cache itself is written from inside
    /// `body` on a miss, so it stays unobserved or that write would
    /// invalidate every other view that read the list.
    private var listStateGeneration = 0
    @ObservationIgnored private var cachedListStateGeneration: Int?
    @ObservationIgnored private var cachedListState: ListState?

    @ObservationIgnored private var normalizedQuerySource = ""
    @ObservationIgnored private var normalizedQueryNeedle = ""
    /// Per-row normalized search fields and document titles. Rebuilt on
    /// `replaceRows`, not on query changes, so a keystroke only runs
    /// `contains` checks.
    @ObservationIgnored
    private var searchIndexByID: [String: SearchIndex] = [:]

    public init(
        rows: [ProjectRow] = [],
        organizations: [OrganizationRecord] = []
    ) {
        self.rows = rows
        self.organizations = organizations
        self.selectedID = rows.first(where: { $0.curation.isFavorite })?.id ?? rows.first?.id
        rebuildSearchIndex()
    }

    public var totalCount: Int { rows.filter { !$0.curation.isHidden && !isArchivedAndHidden($0) }.count }

    public var visibleRows: [ProjectRow] {
        listState().visibleRows
    }

    private func isArchivedAndHidden(_ row: ProjectRow) -> Bool {
        hideArchivedProjects && row.project.isArchived
    }

    public var curationSnapshot: [ProjectCuration] {
        rows.map(\.curation)
    }

    public var organizationSnapshot: [PersistedOrganization] {
        organizations.map { PersistedOrganization(id: $0.id, name: $0.name, isFavorite: $0.isFavorite) }
    }

    /// 1-based Cmd+N legend index for every current favorite, keyed by row id.
    public var favoriteIndexByID: [String: Int] {
        listState().favoriteIndexByID
    }

    public var groups: [ProjectGroup] {
        listState().groups
    }

    public var flatVisibleIDs: [String] {
        listState().flatVisibleIDs
    }

    /// Projects eligible for presence connections and live document search fan-out.
    public func eligibleProjectIDs() -> [String] {
        eligibleRows().map(\.id)
    }

    private func eligibleRows() -> [ProjectRow] {
        rows.filter { row in
            !row.curation.isHidden && !row.isUnavailable && !isArchivedAndHidden(row)
        }
    }

    /// Eligible projects capped by recency — limits presence/socket fan-out on large accounts.
    public func eligibleProjectIDsForPresence(maxCount: Int = 40) -> [String] {
        sortedByRecency(eligibleRows()).prefix(maxCount).map(\.id)
    }

    /// Cached document title matches from recent activity — instant first paint
    /// while live GROQ search runs for the same project.
    public func cachedDocumentMatches(for row: ProjectRow) -> [EditedDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return cachedTitleMatches(forProjectID: row.id, needle: normalizedSearchNeedle)
    }

    private func listInputDidChange(_ changed: Bool) {
        guard changed else { return }
        invalidateListCache()
        reconcileSelection()
    }

    public func clearDocumentSearchState() {
        guard !liveDocumentMatchesByProject.isEmpty || !searchingProjectIDs.isEmpty else { return }
        liveDocumentMatchesByProject = [:]
        searchingProjectIDs = []
        invalidateListCache()
    }

    public func setSearchingProjectIDs(_ ids: Set<String>) {
        guard searchingProjectIDs != ids else { return }
        let previous = searchingProjectIDs
        searchingProjectIDs = ids
        // Header spinner observes `searchingProjectIDs` directly. Skip list
        // invalidation when flipping searching↔idle would show the same docs
        // (common after painting local matches that equal cached titles).
        let flipped = previous.symmetricDifference(ids)
        for id in flipped where searchIndexByID[id] != nil {
            let cached = cachedTitleMatches(forProjectID: id, needle: normalizedSearchNeedle)
            let idle = liveDocumentMatchesByProject[id] ?? cached
            let before = previous.contains(id) ? cached : idle
            let after = ids.contains(id) ? cached : idle
            if before != after {
                invalidateListCache()
                return
            }
        }
    }

    /// Applies live search results in one observable update per batch.
    public func applyDocumentSearchBatch(
        updates: [String: [EditedDocument]],
        completedProjectIDs: Set<String>
    ) {
        guard !updates.isEmpty || !completedProjectIDs.isEmpty else { return }
        var documentsChanged = false
        if !updates.isEmpty {
            for (id, docs) in updates {
                if liveDocumentMatchesByProject[id] != docs {
                    documentsChanged = true
                    break
                }
            }
            liveDocumentMatchesByProject.merge(updates) { _, new in new }
        }
        if !completedProjectIDs.isEmpty {
            searchingProjectIDs.subtract(completedProjectIDs)
        }
        // Always invalidate when document payloads change. Completing a search
        // with identical docs still needs an invalidate when the project leaves
        // `searchingProjectIDs` and switches cached→live source — handled above
        // when payloads differ; when they match, skip.
        if documentsChanged {
            invalidateListCache()
        } else if !completedProjectIDs.isEmpty {
            for id in completedProjectIDs where searchIndexByID[id] != nil {
                let cached = cachedTitleMatches(forProjectID: id, needle: normalizedSearchNeedle)
                let live = liveDocumentMatchesByProject[id] ?? cached
                if live != cached {
                    invalidateListCache()
                    return
                }
            }
        }
    }

    private func listState() -> ListState {
        if cachedListStateGeneration == listStateGeneration, let cached = cachedListState {
            return cached
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !trimmed.isEmpty
        let needle = normalizedSearchNeedle

        var documentsByProjectID: [String: [EditedDocument]] = [:]
        if isSearching {
            documentsByProjectID.reserveCapacity(rows.count)
            for row in rows where !row.curation.isHidden && !isArchivedAndHidden(row) {
                documentsByProjectID[row.id] = matchingDocuments(for: row)
            }
        }

        let visible = computeVisibleRows(
            documentsByProjectID: documentsByProjectID,
            needle: needle,
            isSearching: isSearching
        )
        let favorites = sortedByRecency(visible.filter(\.curation.isFavorite))
        let groups = computeGroups(
            from: visible,
            favorites: favorites,
            documentsByProjectID: documentsByProjectID,
            isSearching: isSearching
        )
        let flatVisibleIDs = groups.flatMap { $0.items.map(\.id) }
        var favoriteIndexByID: [String: Int] = [:]
        for (index, row) in favorites.prefix(9).enumerated() {
            favoriteIndexByID[row.id] = index + 1
        }

        let state = ListState(
            visibleRows: visible,
            groups: groups,
            flatVisibleIDs: flatVisibleIDs,
            favorites: favorites,
            favoriteIndexByID: favoriteIndexByID
        )
        cachedListState = state
        cachedListStateGeneration = listStateGeneration
        return state
    }

    private func invalidateListCache() {
        listStateGeneration += 1
    }

    private var normalizedSearchNeedle: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuerySource == trimmed { return normalizedQueryNeedle }
        normalizedQuerySource = trimmed
        normalizedQueryNeedle = Self.normalize(trimmed)
        return normalizedQueryNeedle
    }

    private func computeVisibleRows(
        documentsByProjectID: [String: [EditedDocument]],
        needle: String,
        isSearching: Bool
    ) -> [ProjectRow] {
        rows.filter { row in
            guard !row.curation.isHidden, !isArchivedAndHidden(row) else { return false }
            guard isSearching else { return true }
            return matches(
                row,
                documents: documentsByProjectID[row.id] ?? [],
                needle: needle
            )
        }
    }

    private func computeGroups(
        from visible: [ProjectRow],
        favorites: [ProjectRow],
        documentsByProjectID: [String: [EditedDocument]],
        isSearching: Bool
    ) -> [ProjectGroup] {
        var result: [ProjectGroup] = []

        // While searching, skip the Favorites pin and fold favorited projects into
        // their normal org / recency groups so results aren't reordered by star.
        if !isSearching {
            if !favorites.isEmpty {
                result.append(ProjectGroup(
                    id: "favorites",
                    title: "Favorites",
                    items: groupItems(from: favorites, documentsByProjectID: documentsByProjectID, isSearching: false)
                ))
            }
        }

        let rest = isSearching ? visible : visible.filter { !$0.curation.isFavorite }
        switch groupBy {
        case .organization:
            let byOrg = Dictionary(grouping: rest) { $0.project.organizationId ?? "" }
            let pinned = organizations.filter(\.isFavorite)
            let unpinned = organizations.filter { !$0.isFavorite }
            let orgOrder = isSearching ? organizations : pinned + unpinned
            var seen = Set<String>()
            for org in orgOrder {
                seen.insert(org.id)
                guard let items = byOrg[org.id], !items.isEmpty else { continue }
                result.append(ProjectGroup(
                    id: org.id,
                    title: org.name,
                    organizationId: org.id,
                    items: groupItems(from: sortedByRecency(items), documentsByProjectID: documentsByProjectID, isSearching: isSearching)
                ))
            }
            let leftoverKeys = byOrg.keys.filter { !$0.isEmpty && !seen.contains($0) }
            for id in leftoverKeys.sorted(by: { lhs, rhs in
                (byOrg[lhs]?.first?.project.organizationName ?? lhs)
                    .localizedCaseInsensitiveCompare(byOrg[rhs]?.first?.project.organizationName ?? rhs)
                    == .orderedAscending
            }) {
                guard let items = byOrg[id], !items.isEmpty else { continue }
                let title = items.first?.project.organizationName ?? id
                result.append(ProjectGroup(
                    id: id,
                    title: title,
                    organizationId: id,
                    items: groupItems(from: sortedByRecency(items), documentsByProjectID: documentsByProjectID, isSearching: isSearching)
                ))
            }
            if let orphans = byOrg[""], !orphans.isEmpty {
                result.append(ProjectGroup(
                    id: "other",
                    title: "Other",
                    items: groupItems(from: sortedByRecency(orphans), documentsByProjectID: documentsByProjectID, isSearching: isSearching)
                ))
            }
        case .lastEdited:
            var buckets: [RecencyBucket: [ProjectRow]] = [:]
            let now = Date()
            for row in rest {
                let bucket: RecencyBucket
                if let edited = row.activity.lastEditedDocument?.editedAt {
                    bucket = RecencyBucket.bucket(for: edited, now: now)
                } else {
                    bucket = .earlier
                }
                buckets[bucket, default: []].append(row)
            }
            for bucket in RecencyBucket.allCases {
                guard let items = buckets[bucket], !items.isEmpty else { continue }
                result.append(ProjectGroup(
                    id: bucket.rawValue,
                    title: bucket.title,
                    items: groupItems(from: sortedByRecency(items), documentsByProjectID: documentsByProjectID, isSearching: isSearching)
                ))
            }
        }
        return result
    }

    /// Interleaves document search rows immediately after each project when a
    /// query is active; otherwise returns plain project rows.
    private func groupItems(
        from projects: [ProjectRow],
        documentsByProjectID: [String: [EditedDocument]],
        isSearching: Bool
    ) -> [PopoverListItem] {
        guard isSearching else {
            return projects.map { .project($0) }
        }
        var items: [PopoverListItem] = []
        items.reserveCapacity(projects.count)
        for project in projects {
            items.append(.project(project))
            for document in documentsByProjectID[project.id] ?? [] {
                items.append(.document(project: project, document: document))
            }
        }
        return items
    }

    /// Documents matching the active query for a project — live Sanity results
    /// when available, cached title matches while search is pending.
    func matchingDocuments(for row: ProjectRow) -> [EditedDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if !searchingProjectIDs.contains(row.id), let live = liveDocumentMatchesByProject[row.id] {
            return live.filter { !Self.excludedSearchTypeNames.contains($0.typeName) }
        }
        return cachedTitleMatches(forProjectID: row.id, needle: normalizedSearchNeedle)
    }

    /// Plugin / infra types that can still sit in the local recent-docs cache
    /// from older syncs — keep them out of interleaved search rows. Cached
    /// titles are dropped when the search index is built.
    nonisolated private static let excludedSearchTypeNames: Set<String> = [
        "vercel.deploymentTarget",
        "webhook_deploy",
    ]

    private func cachedTitleMatches(forProjectID id: String, needle: String) -> [EditedDocument] {
        guard let index = searchIndexByID[id] else { return [] }
        var seen = Set<String>()
        var result: [EditedDocument] = []
        for entry in index.recentDocuments where entry.title.matches(needle) {
            if seen.insert(entry.document.listItemID).inserted {
                result.append(entry.document)
            }
        }
        if let lastEdited = index.lastEditedDocument, lastEdited.title.matches(needle),
           seen.insert(lastEdited.document.listItemID).inserted
        {
            result.insert(lastEdited.document, at: 0)
        }
        return result
    }

    /// Newest last-edited document first; projects with no activity data sink to the bottom.
    private func sortedByRecency(_ items: [ProjectRow]) -> [ProjectRow] {
        items.sorted { lhs, rhs in
            switch (lhs.activity.lastEditedDocument?.editedAt, rhs.activity.lastEditedDocument?.editedAt) {
            case let (l?, r?): return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return false
            }
        }
    }

    public var selectedListItem: PopoverListItem? {
        guard let selectedID else { return nil }
        for group in groups {
            if let item = group.items.first(where: { $0.id == selectedID }) {
                return item
            }
        }
        return nil
    }

    public var selectedRow: ProjectRow? {
        if let selectedListItem {
            return selectedListItem.projectRow
        }
        guard let selectedID else { return nil }
        return visibleRows.first { $0.id == selectedID } ?? rows.first { $0.id == selectedID }
    }

    public func replaceRows(_ rows: [ProjectRow], organizations: [OrganizationRecord]) {
        let previous = selectedID
        self.rows = rows
        self.organizations = organizations
        rebuildSearchIndex()
        if let previous, rows.contains(where: { $0.id == previous }) {
            selectedID = previous
        } else {
            selectedID = rows.first(where: { $0.curation.isFavorite })?.id ?? rows.first?.id
        }
        invalidateListCache()
        reconcileSelection()
        onRowsReplaced?()
    }

    public func clearLiveRows() {
        clearActiveUsers()
        replaceRows([], organizations: [])
    }

    /// Stable per-project presence board. Avatar views must observe
    /// `presenceSlice(for:).members`; the memoized list snapshot carries no
    /// presence, so a tick never rebuilds the list.
    public func presenceSlice(for projectID: String) -> PresenceSlice {
        if let existing = presenceSlices[projectID] { return existing }
        let slice = PresenceSlice()
        presenceSlices[projectID] = slice
        return slice
    }

    /// Live members currently shown for a project.
    public func activeUsers(for projectID: String) -> [Member] {
        presenceSlices[projectID]?.members ?? []
    }

    /// Updates live presence without invalidating list derivation, so a
    /// presence push never disturbs selection or scroll reconciliation.
    /// Only the matching `PresenceSlice` publishes, so other rows stay quiet.
    public func setActiveUsers(_ members: [Member], forProjectID id: String) {
        guard rows.contains(where: { $0.id == id }) else { return }
        let slice = presenceSlice(for: id)
        guard slice.members != members else { return }
        slice.members = members
    }

    /// Drops every live presence entry. Used when the popover closes and on
    /// sign-out so the next open doesn't flash yesterday's editors.
    public func clearActiveUsers() {
        guard !presenceSlices.isEmpty else { return }
        for slice in presenceSlices.values where !slice.members.isEmpty {
            slice.members = []
        }
        presenceSlices.removeAll()
    }

    public func prepareForOpen() {
        searchFocusToken &+= 1
        reconcileSelection()
    }

    public func reconcileSelection() {
        let ids = flatVisibleIDs
        if ids.isEmpty {
            selectedID = nil
            return
        }
        if let selectedID, ids.contains(selectedID) { return }
        self.selectedID = ids.first
    }

    public func selectNext() {
        let ids = flatVisibleIDs
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            self.selectedID = ids[min(index + 1, ids.count - 1)]
        } else {
            selectedID = ids.first
        }
    }

    public func selectPrevious() {
        let ids = flatVisibleIDs
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            self.selectedID = ids[max(index - 1, 0)]
        } else {
            selectedID = ids.last
        }
    }

    public func select(_ id: String) {
        selectedID = id
    }

    public func toggleFavorite(_ id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        var row = rows[index]
        row.curation.isFavorite.toggle()
        rows[index] = row
        invalidateListCache()
        reconcileSelection()
        onCurationChanged?()
    }

    public func toggleFavoriteOnSelection() {
        guard let projectID = selectedListItem?.projectRow.id else { return }
        toggleFavorite(projectID)
    }

    public func cycleGroupBy() {
        let all = GroupBy.allCases
        guard let index = all.firstIndex(of: groupBy) else { return }
        groupBy = all[(index + 1) % all.count]
    }

    public func isOrganizationFavorite(_ id: String) -> Bool {
        organizations.first(where: { $0.id == id })?.isFavorite ?? false
    }

    public func toggleOrganizationFavorite(_ id: String) {
        if let index = organizations.firstIndex(where: { $0.id == id }) {
            var org = organizations[index]
            org.isFavorite.toggle()
            organizations[index] = org
            invalidateListCache()
            onCurationChanged?()
            return
        }
        let name = rows.first(where: { $0.project.organizationId == id })?.project.organizationName ?? id
        organizations.append(OrganizationRecord(id: id, name: name, isFavorite: true))
        invalidateListCache()
        onCurationChanged?()
    }

    public func jumpToFavorite(_ oneBasedIndex: Int) {
        let favorites = listState().favorites
        guard favorites.indices.contains(oneBasedIndex - 1) else { return }
        selectedID = favorites[oneBasedIndex - 1].id
    }

    /// Tracks Command hold for revealing favorite shortcut legends after 0.3s.
    /// Does not restart the timer while Command stays down (e.g. adding Option).
    public func updateCommandKeyHeld(_ isHeld: Bool) {
        if isHeld {
            guard commandHoldRevealTask == nil, !showFavoriteShortcutLegends else { return }
            commandHoldRevealTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                showFavoriteShortcutLegends = true
            }
        } else {
            commandHoldRevealTask?.cancel()
            commandHoldRevealTask = nil
            showFavoriteShortcutLegends = false
        }
    }

    public func copySelectedProjectID() {
        guard let projectID = selectedListItem?.projectRow.id else { return }
        copy(projectID, key: "project:\(projectID)")
    }

    public func copyProjectID(_ id: String) {
        copy(id, key: "project:\(id)")
    }

    public func copyOrganizationID(_ id: String) {
        copy(id, key: "org:\(id)")
    }

    public var copiedProjectID: String? {
        guard let copiedKey, copiedKey.hasPrefix("project:") else { return nil }
        return String(copiedKey.dropFirst("project:".count))
    }

    public var copiedOrganizationID: String? {
        guard let copiedKey, copiedKey.hasPrefix("org:") else { return nil }
        return String(copiedKey.dropFirst("org:".count))
    }

    public func refresh() {
        onRefreshRequested?()
    }

    public func clearQueryOrSignalDismiss() -> Bool {
        guard !query.isEmpty else { return true }
        clearDocumentSearchState()
        query = ""
        return false
    }

    private func copy(_ value: String, key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedKey = key
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            if copiedKey == key {
                copiedKey = nil
            }
        }
    }

    private func matches(
        _ row: ProjectRow,
        documents: [EditedDocument],
        needle: String
    ) -> Bool {
        if !documents.isEmpty { return true }
        let fields = searchIndex(for: row).fields
        return fields.contains { $0.matches(needle) }
    }

    /// A string folded for search once up front, plus its word initials.
    private struct SearchText {
        let text: String
        let initials: String

        init(_ raw: String) {
            text = StudioStore.normalize(raw)
            initials = StudioStore.initials(of: text)
        }

        func matches(_ needle: String) -> Bool {
            text.contains(needle) || initials.contains(needle)
        }
    }

    private struct IndexedDocument {
        let document: EditedDocument
        let title: SearchText

        init(_ document: EditedDocument) {
            self.document = document
            title = SearchText(document.title)
        }
    }

    private struct SearchIndex {
        /// Project / org / id / dataset / link fields; document titles are
        /// matched separately through `cachedTitleMatches`.
        var fields: [SearchText]
        var recentDocuments: [IndexedDocument]
        var lastEditedDocument: IndexedDocument?

        init(_ row: ProjectRow) {
            let rawFields: [String] = [
                row.displayTitle,
                row.project.displayName,
                row.curation.nickname ?? "",
                row.project.organizationName ?? "",
                row.project.organizationId ?? "",
                row.project.id,
                row.project.datasets.map(\.name).joined(separator: " "),
                row.curation.frontendLinks.map(\.label).joined(separator: " "),
                row.curation.extraStudioLinks.map(\.label).joined(separator: " "),
            ]
            fields = rawFields.map(SearchText.init).filter { !$0.text.isEmpty }
            func isSearchable(_ document: EditedDocument) -> Bool {
                !StudioStore.excludedSearchTypeNames.contains(document.typeName)
            }
            recentDocuments = row.activity.recentDocuments.filter(isSearchable).map(IndexedDocument.init)
            lastEditedDocument = row.activity.lastEditedDocument.flatMap { isSearchable($0) ? IndexedDocument($0) : nil }
        }
    }

    private func rebuildSearchIndex() {
        var next: [String: SearchIndex] = [:]
        next.reserveCapacity(rows.count)
        for row in rows {
            next[row.id] = SearchIndex(row)
        }
        searchIndexByID = next
    }

    private func searchIndex(for row: ProjectRow) -> SearchIndex {
        if let cached = searchIndexByID[row.id] { return cached }
        let built = SearchIndex(row)
        searchIndexByID[row.id] = built
        return built
    }

    nonisolated private static func normalize(_ string: String) -> String {
        let folded = string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let separatorsNormalized = folded
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return separatorsNormalized
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// First letter of each word, e.g. "elevate experiences" -> "ee", so a
    /// query like "ee" matches "Elevate Experiences" the way an acronym would.
    nonisolated private static func initials(of normalizedString: String) -> String {
        normalizedString
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }
}
