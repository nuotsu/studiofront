import AppKit
import Foundation
import Observation

public enum ListIsolation: Hashable, Sendable {
    case organization(String)
    case recency(RecencyBucket)
}

@MainActor
@Observable
public final class StudioStore {
    public var rows: [ProjectRow] {
        didSet {
            previewRowsCache = [:]
            browseRowsCache = nil
            rowIndexCache = nil
        }
    }
    public var organizations: [OrganizationRecord] {
        didSet {
            orderedOrganizationsCache = nil
            let pinned = Set(organizations.lazy.filter(\.isFavorite).map(\.id))
            if pinned != pinnedOrganizationIDs { pinnedOrganizationIDs = pinned }
        }
    }
    /// Ids of pinned organizations. Stored (and observed on its own) so the
    /// sidebar rows and section headers that ask "is this org pinned?" only
    /// redraw when the pinned set changes, and the lookup is O(1).
    public private(set) var pinnedOrganizationIDs: Set<String> = []
    // The list inputs below invalidate the memoized list themselves, so the
    // first render after a change (e.g. a keystroke) already shows the new
    // results instead of one stale frame plus a second render from `.onChange`.
    public var query: String = "" {
        didSet {
            if queryInput != query { queryInput = query }
            listInputDidChange(query != oldValue)
        }
    }
    /// The text in the search field. Typing updates this at once, so the
    /// field always echoes keystrokes immediately; `query` (which filters
    /// and redraws the list) follows after `queryApplyDelay` without a new
    /// keystroke. Fast typing therefore redraws the list once, not once per
    /// character. Clearing the field applies immediately.
    public var queryInput: String = "" {
        didSet {
            guard queryInput != oldValue else { return }
            queryApplyTask?.cancel()
            queryApplyTask = nil
            guard queryInput != query else { return }
            if queryInput.isEmpty {
                query = ""
                return
            }
            queryApplyTask = Task { [weak self] in
                try? await Task.sleep(for: Self.queryApplyDelay)
                guard !Task.isCancelled else { return }
                self?.flushQueryInput()
            }
        }
    }
    public static let queryApplyDelay: Duration = .milliseconds(90)
    @ObservationIgnored private var queryApplyTask: Task<Void, Never>?

    /// Applies any typed-but-pending search text now. Call before acting on
    /// the list (arrow keys, Return, Esc) so the action sees current results.
    public func flushQueryInput() {
        queryApplyTask?.cancel()
        queryApplyTask = nil
        if query != queryInput { query = queryInput }
    }
    public var groupBy: GroupBy = .organization {
        didSet {
            if groupBy != oldValue { isolation = nil }
            listInputDidChange(groupBy != oldValue)
        }
    }
    public var selectedID: String?
    public var copiedKey: String?
    public var searchFocusToken: UInt = 0
    public var isRefreshing: Bool = false
    public var hideArchivedProjects: Bool = true {
        didSet {
            previewRowsCache = [:]
            browseRowsCache = nil
            listInputDidChange(hideArchivedProjects != oldValue)
        }
    }
    /// Organizations the user hid from the sidebar. Their projects drop out of
    /// the browse list (Favorites included) but still show up in search.
    public var hiddenOrganizationIDs: Set<String> = [] {
        didSet {
            browseRowsCache = nil
            listInputDidChange(hiddenOrganizationIDs != oldValue)
        }
    }
    /// Fired after the user hides or shows an organization, so the app can
    /// persist the set and re-scope presence connections.
    public var onHiddenOrganizationsChanged: (() -> Void)?
    /// User-chosen order of pinned organizations (ids). Pinned orgs missing
    /// from it keep their directory order after the listed ones.
    public var pinnedOrganizationOrder: [String] = [] {
        didSet {
            orderedOrganizationsCache = nil
            listInputDidChange(pinnedOrganizationOrder != oldValue)
        }
    }
    public var onPinnedOrganizationOrderChanged: (() -> Void)?
    /// Organization isolated in the main column, including hidden orgs. Not persisted.
    public var isolation: ListIsolation? {
        didSet { listInputDidChange(isolation != oldValue) }
    }
    public var revealedOrganizationID: String? {
        get { if case let .organization(id) = isolation { return id }; return nil }
        set { isolation = newValue.map(ListIsolation.organization) }
    }
    public var isolatedRecencyBucket: RecencyBucket? {
        get { if case let .recency(bucket) = isolation { return bucket }; return nil }
        set { isolation = newValue.map(ListIsolation.recency) }
    }
    /// User-chosen order of pinned projects (ids). Pinned projects missing
    /// from it follow the listed ones, newest edit first.
    public var pinnedProjectOrder: [String] = [] {
        didSet { listInputDidChange(pinnedProjectOrder != oldValue) }
    }
    public var onPinnedProjectOrderChanged: (() -> Void)?
    /// True once the arrow keys move the selection; a mouse click or a new
    /// popover session clears it. The selected row is only highlighted
    /// while this is on.
    public var isKeyboardNavigating = false

    @ObservationIgnored private var previewRowsCache: [String: [ProjectRow]] = [:]
    @ObservationIgnored private var browseRowsCache: [ProjectRow]?
    @ObservationIgnored private var rowIndexCache: [String: Int]?
    @ObservationIgnored private var orderedOrganizationsCache: [OrganizationRecord]?
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
    @ObservationIgnored private var cachedSidebarGroups: [ProjectGroup]?
    private var listStateGeneration = 0
    @ObservationIgnored private var cachedListStateGeneration: Int?
    @ObservationIgnored private var cachedListState: ListState?

    @ObservationIgnored private var normalizedQuerySource = ""
    @ObservationIgnored private var normalizedQueryNeedle: [UInt8] = []
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
        self.pinnedOrganizationIDs = Set(organizations.lazy.filter(\.isFavorite).map(\.id))
        self.selectedID = rows.first(where: { $0.curation.isFavorite })?.id ?? rows.first?.id
        rebuildSearchIndex()
    }

    /// O(1) row lookup by project id (presence ticks and curation edits used
    /// to scan the whole list).
    public func row(withID id: String) -> ProjectRow? {
        rowIndex(for: id).map { rows[$0] }
    }

    private func rowIndex(for id: String) -> Int? {
        if let rowIndexCache { return rowIndexCache[id] }
        var index: [String: Int] = [:]
        index.reserveCapacity(rows.count)
        for (offset, row) in rows.enumerated() where index[row.id] == nil {
            index[row.id] = offset
        }
        rowIndexCache = index
        return index[id]
    }

    public var totalCount: Int { rows.filter { !$0.curation.isHidden && !isArchivedAndHidden($0) }.count }

    public var visibleRows: [ProjectRow] {
        listState().visibleRows
    }

    private func isArchivedAndHidden(_ row: ProjectRow) -> Bool {
        hideArchivedProjects && row.project.isArchived
    }

    private func isInHiddenOrganization(_ row: ProjectRow) -> Bool {
        guard !hiddenOrganizationIDs.isEmpty, let orgID = row.project.organizationId else { return false }
        return hiddenOrganizationIDs.contains(orgID)
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

    /// Sidebar sections remain stable while the main column is isolated.
    public var sidebarGroups: [ProjectGroup] {
        if isolation == nil && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return groups }
        _ = listStateGeneration
        if let cachedSidebarGroups { return cachedSidebarGroups }
        let visible = browseRows
        let result = computeGroups(from: visible, favorites: orderedPinned(visible.filter(\.curation.isFavorite)), documentsByProjectID: [:], isSearching: false, applyIsolation: false)
        cachedSidebarGroups = result
        return result
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
        sortedByRecency(eligibleRows().filter { !isInHiddenOrganization($0) }).prefix(maxCount).map(\.id)
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
                documentsByProjectID[row.id] = matchingDocuments(forProjectID: row.id, needle: needle)
            }
        }

        let visible = computeVisibleRows(
            documentsByProjectID: documentsByProjectID,
            needle: needle,
            isSearching: isSearching
        )
        let favorites = orderedPinned(visible.filter(\.curation.isFavorite))
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
        cachedSidebarGroups = nil
        listStateGeneration += 1
    }

    /// The query, folded the same way as the search index, as UTF-8.
    private var normalizedSearchNeedle: [UInt8] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuerySource == trimmed { return normalizedQueryNeedle }
        normalizedQuerySource = trimmed
        normalizedQueryNeedle = Array(Self.normalize(trimmed).utf8)
        return normalizedQueryNeedle
    }

    private func computeVisibleRows(
        documentsByProjectID: [String: [EditedDocument]],
        needle: [UInt8],
        isSearching: Bool
    ) -> [ProjectRow] {
        rows.filter { row in
            guard !row.curation.isHidden, !isArchivedAndHidden(row) else { return false }
            if let revealedOrganizationID, row.project.organizationId != revealedOrganizationID { return false }
            if let isolatedRecencyBucket, recencyBucket(for: row) != isolatedRecencyBucket { return false }
            guard isSearching else {
                return revealedOrganizationID != nil || !isInHiddenOrganization(row)
            }
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
        isSearching: Bool,
        applyIsolation: Bool = true
    ) -> [ProjectGroup] {
        var result: [ProjectGroup] = []
        var rest = visible

        // While searching, skip the Favorites pin and fold favorited projects into
        // their normal org / recency groups so results aren't reordered by star.
        // Projects whose own name matches are pinned in "Studios" instead, and
        // only repeat below when they also carry matching documents.
        if isSearching {
            let needle = normalizedSearchNeedle
            let studioMatches = sortedByRecency(visible.filter { row in
                searchIndex(for: row).titleFields.contains { $0.matches(needle) }
            })
            if !studioMatches.isEmpty {
                result.append(ProjectGroup(
                    id: Self.studiosGroupID,
                    title: "Studios",
                    items: studioMatches.map { .studio($0) }
                ))
                let studioIDs = Set(studioMatches.map(\.id))
                rest = visible.filter { row in
                    !studioIDs.contains(row.id) || !(documentsByProjectID[row.id] ?? []).isEmpty
                }
            }
        } else if groupBy == .organization {
            // Pinned only leads the Organizations view; by date, pinned
            // projects sit in their recency buckets like the rest.
            // Pinned projects also stay in their org section; the Pinned copy
            // gets its own item id so selection and scrolling stay distinct.
            if !favorites.isEmpty && (!applyIsolation || isolation == nil) {
                result.append(ProjectGroup(
                    id: Self.favoritesGroupID,
                    title: "Pinned",
                    items: favorites.map { .pinned($0) }
                ))
            }
        }

        switch groupBy {
        case .organization:
            let byOrg = Dictionary(grouping: rest) { $0.project.organizationId ?? "" }
            let hiddenByOrg = isSearching ? [:] : hiddenRowsByOrganization(applyIsolation: applyIsolation)
            let orgOrder = isSearching ? organizations : orderedOrganizations
            var seen = Set<String>()
            for org in orgOrder {
                seen.insert(org.id)
                let items = byOrg[org.id] ?? []
                let hidden = hiddenByOrg[org.id] ?? []
                guard !items.isEmpty || !hidden.isEmpty else { continue }
                result.append(ProjectGroup(
                    id: org.id,
                    title: org.name,
                    organizationId: org.id,
                    items: groupItems(from: sortedByRecency(items), documentsByProjectID: documentsByProjectID, isSearching: isSearching),
                    hiddenRows: hidden
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
                buckets[recencyBucket(for: row, now: now), default: []].append(row)
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

    private func recencyBucket(for row: ProjectRow, now: Date = Date()) -> RecencyBucket {
        row.activity.lastEditedDocument.map { RecencyBucket.bucket(for: $0.editedAt, now: now) } ?? .earlier
    }

    public static let favoritesGroupID = "favorites"
    public static let studiosGroupID = "studios"

    /// Hidden projects per org for the sections' "hidden" dropdowns, limited
    /// to orgs the browse list (or the isolated view) shows.
    private func hiddenRowsByOrganization(applyIsolation: Bool) -> [String: [ProjectRow]] {
        var result: [String: [ProjectRow]] = [:]
        for row in rows where row.curation.isHidden && !isArchivedAndHidden(row) {
            guard let orgID = row.project.organizationId else { continue }
            if applyIsolation, let revealedOrganizationID {
                guard orgID == revealedOrganizationID else { continue }
            } else if isInHiddenOrganization(row) {
                continue
            }
            result[orgID, default: []].append(row)
        }
        return result.mapValues { rows in
            rows.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
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
        return matchingDocuments(forProjectID: row.id, needle: normalizedSearchNeedle)
    }

    private func matchingDocuments(forProjectID id: String, needle: [UInt8]) -> [EditedDocument] {
        if !searchingProjectIDs.contains(id), let live = liveDocumentMatchesByProject[id] {
            return live.filter { !Self.excludedSearchTypeNames.contains($0.typeName) }
        }
        return cachedTitleMatches(forProjectID: id, needle: needle)
    }

    /// Plugin / infra types that can still sit in the local recent-docs cache
    /// from older syncs — keep them out of interleaved search rows. Cached
    /// titles are dropped when the search index is built.
    nonisolated static let excludedSearchTypeNames: Set<String> = [
        "vercel.deploymentTarget",
        "webhook_deploy",
    ]

    private func cachedTitleMatches(forProjectID id: String, needle: [UInt8]) -> [EditedDocument] {
        guard let index = searchIndexByID[id] else { return [] }
        // Most projects match nothing; only build the dedupe set once
        // something does.
        var seen: Set<String>?
        var result: [EditedDocument] = []
        for entry in index.recentDocuments where entry.title.matches(needle) {
            if seen == nil { seen = [] }
            if seen!.insert(entry.document.listItemID).inserted {
                result.append(entry.document)
            }
        }
        if let lastEdited = index.lastEditedDocument, lastEdited.title.matches(needle),
           !(seen?.contains(lastEdited.document.listItemID) ?? false)
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
        // A refresh that changed nothing (the usual result when the popover
        // reopens) leaves the list, selection, presence and search caches
        // alone instead of rebuilding and redrawing everything.
        if rows == self.rows, organizations == self.organizations { return }
        let previous = selectedID
        self.rows = rows
        self.organizations = organizations
        rebuildSearchIndex()
        if let previous, rowIndex(for: previous) != nil {
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
        guard rowIndex(for: id) != nil else { return }
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
        isKeyboardNavigating = false
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
        isKeyboardNavigating = true
        let ids = flatVisibleIDs
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            self.selectedID = ids[min(index + 1, ids.count - 1)]
        } else {
            selectedID = ids.first
        }
    }

    public func selectPrevious() {
        isKeyboardNavigating = true
        let ids = flatVisibleIDs
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            self.selectedID = ids[max(index - 1, 0)]
        } else {
            selectedID = ids.last
        }
    }

    public func select(_ id: String) {
        isKeyboardNavigating = false
        selectedID = id
    }

    public func toggleFavorite(_ id: String) {
        guard let index = rowIndex(for: id) else { return }
        var row = rows[index]
        row.curation.isFavorite.toggle()
        rows[index] = row
        syncPinnedProjectOrder(id, isPinned: row.curation.isFavorite)
        invalidateListCache()
        reconcileSelection()
        onCurationChanged?()
    }

    /// Pinned projects in the user's order; ones they haven't placed follow,
    /// newest edit first.
    private func orderedPinned(_ pinned: [ProjectRow]) -> [ProjectRow] {
        let byRecency = sortedByRecency(pinned)
        guard !pinnedProjectOrder.isEmpty else { return byRecency }
        let rank = Dictionary(pinnedProjectOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return byRecency.enumerated().sorted { lhs, rhs in
            let l = rank[lhs.element.id] ?? Int.max
            let r = rank[rhs.element.id] ?? Int.max
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }

    private var pinnedProjectIDsInOrder: [String] {
        orderedPinned(browseRows.filter(\.curation.isFavorite)).map(\.id)
    }

    /// Moves a pinned project up (-1) or down (+1) in the Pinned group.
    public func movePinnedProject(_ id: String, by offset: Int) {
        var order = pinnedProjectIDsInOrder
        guard let index = order.firstIndex(of: id) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        pinnedProjectOrder = order
        onPinnedProjectOrderChanged?()
    }

    public func canMovePinnedProject(_ id: String, by offset: Int) -> Bool {
        let order = pinnedProjectIDsInOrder
        guard let index = order.firstIndex(of: id) else { return false }
        return order.indices.contains(index + offset)
    }

    private func syncPinnedProjectOrder(_ id: String, isPinned: Bool) {
        // Only maintained once the user has ordered pins by hand; until then
        // pins sort by recency.
        guard !pinnedProjectOrder.isEmpty else { return }
        var order = pinnedProjectOrder
        if isPinned {
            if !order.contains(id) { order.append(id) }
        } else {
            order.removeAll { $0 == id }
        }
        guard order != pinnedProjectOrder else { return }
        pinnedProjectOrder = order
        onPinnedProjectOrderChanged?()
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
        pinnedOrganizationIDs.contains(id)
    }

    public func toggleOrganizationFavorite(_ id: String) {
        if let index = organizations.firstIndex(where: { $0.id == id }) {
            var org = organizations[index]
            org.isFavorite.toggle()
            organizations[index] = org
            syncPinnedOrder(id, isPinned: org.isFavorite)
            invalidateListCache()
            onCurationChanged?()
            return
        }
        syncPinnedOrder(id, isPinned: true)
        let name = rows.first(where: { $0.project.organizationId == id })?.project.organizationName ?? id
        organizations.append(OrganizationRecord(id: id, name: name, isFavorite: true))
        invalidateListCache()
        onCurationChanged?()
    }

    /// Pinned organizations first, in the user's order, then the rest in
    /// directory order. The sidebar and the list both use this.
    public var orderedOrganizations: [OrganizationRecord] {
        // Read both inputs first so callers still depend on them when the
        // cached result is returned. The sort uses localized comparisons,
        // which are too slow to repeat on every list rebuild.
        let organizations = organizations
        let pinnedOrganizationOrder = pinnedOrganizationOrder
        if let orderedOrganizationsCache { return orderedOrganizationsCache }
        let result = Self.ordered(organizations, pinnedOrder: pinnedOrganizationOrder)
        orderedOrganizationsCache = result
        return result
    }

    private static func ordered(
        _ organizations: [OrganizationRecord],
        pinnedOrder pinnedOrganizationOrder: [String]
    ) -> [OrganizationRecord] {
        let pinned = organizations.filter(\.isFavorite)
        let rank = Dictionary(pinnedOrganizationOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sortedPinned = pinned.enumerated().sorted { lhs, rhs in
            let l = rank[lhs.element.id] ?? Int.max
            let r = rank[rhs.element.id] ?? Int.max
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
        return sortedPinned + organizations.filter { !$0.isFavorite }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Moves a pinned organization up (-1) or down (+1) among pinned orgs.
    public func movePinnedOrganization(_ id: String, by offset: Int) {
        var order = orderedOrganizations.filter(\.isFavorite).map(\.id)
        guard let index = order.firstIndex(of: id) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        pinnedOrganizationOrder = order
        onPinnedOrganizationOrderChanged?()
    }

    /// Whether `movePinnedOrganization(id, by: offset)` would do anything.
    public func canMovePinnedOrganization(_ id: String, by offset: Int) -> Bool {
        let order = orderedOrganizations.filter(\.isFavorite).map(\.id)
        guard let index = order.firstIndex(of: id) else { return false }
        return order.indices.contains(index + offset)
    }

    private func syncPinnedOrder(_ id: String, isPinned: Bool) {
        var order = pinnedOrganizationOrder
        if isPinned {
            if !order.contains(id) { order.append(id) }
        } else {
            order.removeAll { $0 == id }
        }
        guard order != pinnedOrganizationOrder else { return }
        pinnedOrganizationOrder = order
        onPinnedOrganizationOrderChanged?()
    }

    /// Hides or shows a single project (its curation's `isHidden`).
    public func setProjectHidden(_ id: String, hidden: Bool) {
        guard let index = rowIndex(for: id) else { return }
        var row = rows[index]
        guard row.curation.isHidden != hidden else { return }
        row.curation.isHidden = hidden
        rows[index] = row
        invalidateListCache()
        reconcileSelection()
        onCurationChanged?()
    }

    /// The projects the browse list shows when nothing is isolated or
    /// searched: not hidden, not hidden-archived, not in a hidden org.
    public var browseRows: [ProjectRow] {
        if let browseRowsCache { return browseRowsCache }
        let result = rows.filter { !$0.curation.isHidden && !isArchivedAndHidden($0) && !isInHiddenOrganization($0) }
        browseRowsCache = result
        return result
    }

    /// Projects the user hid, by name.
    public var hiddenProjects: [ProjectRow] {
        rows.filter(\.curation.isHidden)
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    /// Up to four of an org's projects for its sidebar preview: pinned
    /// first, then most recently edited. Hidden candidates go last so the
    /// preview can replace them with one indicator when a quadrant is free.
    /// Archived projects respect the current visibility setting.
    public func previewRows(forOrganization id: String, limit: Int = 4) -> [ProjectRow] {
        // Cached per org until `rows` changes: the sidebar asks on every
        // redraw, including each keystroke while searching. Reading `rows`
        // first keeps the caller subscribed to row changes on a cache hit.
        _ = rows.count
        _ = hideArchivedProjects
        if let cached = previewRowsCache[id] { return Array(cached.prefix(limit)) }
        let result = computePreviewRows(forOrganization: id, limit: 4)
        previewRowsCache[id] = result
        return Array(result.prefix(limit))
    }

    private func computePreviewRows(forOrganization id: String, limit: Int) -> [ProjectRow] {
        let members = rows.filter { $0.project.organizationId == id && !isArchivedAndHidden($0) }
        let sorted = members.sorted { lhs, rhs in
            let lHidden = lhs.curation.isHidden
            let rHidden = rhs.curation.isHidden
            if lHidden != rHidden { return !lHidden }
            if lhs.curation.isFavorite != rhs.curation.isFavorite { return lhs.curation.isFavorite }
            switch (lhs.activity.lastEditedDocument?.editedAt, rhs.activity.lastEditedDocument?.editedAt) {
            case let (l?, r?): return l > r
            case (.some, .none): return true
            default: return false
            }
        }
        return Array(sorted.prefix(limit))
    }

    /// Hidden organizations in display order, with names resolved from the
    /// org list or, failing that, any project that belongs to the org.
    public var hiddenOrganizations: [OrganizationRecord] {
        hiddenOrganizationIDs.map { id in
            if let org = organizations.first(where: { $0.id == id }) { return org }
            let name = rows.first(where: { $0.project.organizationId == id })?.project.organizationName ?? id
            return OrganizationRecord(id: id, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func setOrganizationHidden(_ id: String, hidden: Bool) {
        var next = hiddenOrganizationIDs
        if hidden { next.insert(id) } else { next.remove(id) }
        guard next != hiddenOrganizationIDs else { return }
        hiddenOrganizationIDs = next
        onHiddenOrganizationsChanged?()
    }

    /// First selectable list item in a group, for sidebar jumps.
    public func firstItemID(inGroup groupID: String) -> String? {
        groups.first(where: { $0.id == groupID })?.items.first?.id
    }

    /// The group that currently lists `itemID`.
    public func groupID(containing itemID: String) -> String? {
        groups.first(where: { group in group.items.contains { $0.id == itemID } })?.id
    }

    public func jumpToFavorite(_ oneBasedIndex: Int) {
        let favorites = listState().favorites
        guard favorites.indices.contains(oneBasedIndex - 1) else { return }
        let row = favorites[oneBasedIndex - 1]
        isKeyboardNavigating = true
        // The Pinned copy when there is one (Organizations view), else the row.
        let pinnedID = PopoverListItem.pinned(row).id
        selectedID = flatVisibleIDs.contains(pinnedID) ? pinnedID : row.id
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
        guard let item = selectedListItem else { return }
        copy(item.projectRow.id, key: Self.projectIDCopyKey(listItemID: item.id))
    }

    /// Copy-feedback key for the project id chip on one list row.
    public static func projectIDCopyKey(listItemID: String) -> String {
        "item-project:\(listItemID)"
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
        flushQueryInput()
        if query.isEmpty, isolation != nil {
            isolation = nil
            return false
        }
        guard !query.isEmpty else { return true }
        clearDocumentSearchState()
        query = ""
        return false
    }

    /// Copies `value` and shows "copied" only on the chip that owns
    /// `feedbackKey`, so other chips showing the same id stay unchanged.
    public func copy(_ value: String, feedbackKey: String) {
        copy(value, key: feedbackKey)
    }

    public func isShowingCopied(_ feedbackKey: String) -> Bool {
        copiedKey == feedbackKey
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
        needle: [UInt8]
    ) -> Bool {
        if !documents.isEmpty { return true }
        let fields = searchIndex(for: row).fields
        return fields.contains { $0.matches(needle) }
    }

    /// A string folded for search once up front, plus its word initials,
    /// both kept as UTF-8 so a keystroke runs plain byte searches.
    /// (`String.contains` walks grapheme clusters and was the bulk of the
    /// per-keystroke filter time.)
    private struct SearchText {
        let text: [UInt8]
        let initials: [UInt8]

        init(_ raw: String) {
            let normalized = StudioStore.normalize(raw)
            text = Array(normalized.utf8)
            initials = Array(StudioStore.initials(of: normalized).utf8)
        }

        func matches(_ needle: [UInt8]) -> Bool {
            StudioStore.contains(text, needle) || StudioStore.contains(initials, needle)
        }
    }

    /// Byte-wise substring test. An empty needle matches nothing.
    nonisolated private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        return haystack.withUnsafeBytes { hay in
            needle.withUnsafeBytes { pin in
                memmem(hay.baseAddress, hay.count, pin.baseAddress, pin.count) != nil
            }
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
        /// Name fields only, for the pinned "Studios" search group.
        var titleFields: [SearchText]
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
            titleFields = [row.displayTitle, row.project.displayName, row.curation.nickname ?? ""]
                .map(SearchText.init)
                .filter { !$0.text.isEmpty }
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
        let folded = string
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .precomposedStringWithCanonicalMapping
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
