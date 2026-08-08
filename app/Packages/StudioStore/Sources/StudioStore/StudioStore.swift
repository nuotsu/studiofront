import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class StudioStore {
    public var rows: [ProjectRow]
    public var organizations: [OrganizationRecord]
    public var query: String = ""
    public var groupBy: GroupBy = .organization
    public var selectedID: String?
    public var copiedKey: String?
    public var searchFocusToken: UInt = 0
    public var isRefreshing: Bool = false
    public var onCurationChanged: (() -> Void)?
    public var onRefreshRequested: (() -> Void)?

    private var copyResetTask: Task<Void, Never>?

    public init(
        rows: [ProjectRow] = [],
        organizations: [OrganizationRecord] = []
    ) {
        self.rows = rows
        self.organizations = organizations
        self.selectedID = rows.first(where: { $0.curation.isFavorite })?.id ?? rows.first?.id
    }

    public static func fixtures() -> StudioStore {
        StudioStore(
            rows: FixtureData.rows(),
            organizations: FixtureData.organizationOrder.map {
                OrganizationRecord(id: $0.id, name: $0.name)
            }
        )
    }

    public var totalCount: Int { rows.filter { !$0.curation.isHidden }.count }

    public var visibleRows: [ProjectRow] {
        rows.filter { !$0.curation.isHidden && matches($0) }
    }

    public var curationSnapshot: [ProjectCuration] {
        rows.map(\.curation)
    }

    public var organizationSnapshot: [PersistedOrganization] {
        organizations.map { PersistedOrganization(id: $0.id, name: $0.name, isFavorite: $0.isFavorite) }
    }

    public var groups: [ProjectGroup] {
        let visible = visibleRows
        var result: [ProjectGroup] = []

        let favorites = visible.filter(\.curation.isFavorite)
        if !favorites.isEmpty {
            result.append(ProjectGroup(id: "favorites", title: "Favorites", items: favorites))
        }

        let rest = visible.filter { !$0.curation.isFavorite }
        switch groupBy {
        case .organization:
            let pinned = organizations.filter(\.isFavorite)
            let unpinned = organizations.filter { !$0.isFavorite }
            var seen = Set<String>()
            for org in pinned + unpinned {
                seen.insert(org.id)
                let items = rest.filter { $0.project.organizationId == org.id }
                if !items.isEmpty {
                    result.append(ProjectGroup(id: org.id, title: org.name, organizationId: org.id, items: items))
                }
            }
            let leftoverOrgs = Dictionary(grouping: rest.filter { row in
                guard let id = row.project.organizationId else { return false }
                return !seen.contains(id)
            }, by: { $0.project.organizationId ?? "other" })
            for (id, items) in leftoverOrgs.sorted(by: { lhs, rhs in
                (lhs.value.first?.project.organizationName ?? lhs.key)
                    .localizedCaseInsensitiveCompare(rhs.value.first?.project.organizationName ?? rhs.key)
                    == .orderedAscending
            }) {
                let title = items.first?.project.organizationName ?? id
                result.append(ProjectGroup(id: id, title: title, organizationId: id, items: items))
            }
            let orphans = rest.filter { $0.project.organizationId == nil }
            if !orphans.isEmpty {
                result.append(ProjectGroup(id: "other", title: "Other", items: orphans))
            }
        case .lastEdited:
            for bucket in RecencyBucket.allCases {
                let items = rest.filter { row in
                    guard let edited = row.activity.lastEditedDocument?.editedAt else {
                        return bucket == .earlier
                    }
                    return RecencyBucket.bucket(for: edited) == bucket
                }
                if !items.isEmpty {
                    result.append(ProjectGroup(id: bucket.rawValue, title: bucket.title, items: items))
                }
            }
        }
        return result
    }

    public var flatVisibleIDs: [String] {
        groups.flatMap { $0.items.map(\.id) }
    }

    public var selectedRow: ProjectRow? {
        guard let selectedID else { return nil }
        return visibleRows.first { $0.id == selectedID } ?? rows.first { $0.id == selectedID }
    }

    public func replaceRows(_ rows: [ProjectRow], organizations: [OrganizationRecord]) {
        let previous = selectedID
        self.rows = rows
        self.organizations = organizations
        if let previous, rows.contains(where: { $0.id == previous }) {
            selectedID = previous
        } else {
            selectedID = rows.first(where: { $0.curation.isFavorite })?.id ?? rows.first?.id
        }
        reconcileSelection()
    }

    public func clearLiveRows() {
        replaceRows([], organizations: [])
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
            self.selectedID = ids[(index + 1) % ids.count]
        } else {
            selectedID = ids.first
        }
    }

    public func selectPrevious() {
        let ids = flatVisibleIDs
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            self.selectedID = ids[(index - 1 + ids.count) % ids.count]
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
        reconcileSelection()
        onCurationChanged?()
    }

    public func toggleFavoriteOnSelection() {
        guard let selectedID else { return }
        toggleFavorite(selectedID)
    }

    public func isOrganizationFavorite(_ id: String) -> Bool {
        organizations.first(where: { $0.id == id })?.isFavorite ?? false
    }

    public func toggleOrganizationFavorite(_ id: String) {
        if let index = organizations.firstIndex(where: { $0.id == id }) {
            var org = organizations[index]
            org.isFavorite.toggle()
            organizations[index] = org
            onCurationChanged?()
            return
        }
        let name = rows.first(where: { $0.project.organizationId == id })?.project.organizationName ?? id
        organizations.append(OrganizationRecord(id: id, name: name, isFavorite: true))
        onCurationChanged?()
    }

    public func jumpToFavorite(_ oneBasedIndex: Int) {
        let favorites = visibleRows.filter(\.curation.isFavorite)
        guard favorites.indices.contains(oneBasedIndex - 1) else { return }
        selectedID = favorites[oneBasedIndex - 1].id
    }

    public func copySelectedProjectID() {
        guard let id = selectedID else { return }
        copy(id, key: "project:\(id)")
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
        if !query.isEmpty {
            query = ""
            reconcileSelection()
            return false
        }
        return true
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

    private func matches(_ row: ProjectRow) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = normalize(trimmed)
        let fields: [String] = [
            row.displayTitle,
            row.project.displayName,
            row.curation.nickname ?? "",
            row.project.organizationName ?? "",
            row.project.organizationId ?? "",
            row.project.id,
            row.project.datasets.map(\.name).joined(separator: " "),
            row.activity.lastEditedDocument?.title ?? "",
            row.curation.frontendLinks.map(\.label).joined(separator: " "),
            row.curation.extraStudioLinks.map(\.label).joined(separator: " "),
        ]
        return fields.contains { normalize($0).contains(needle) }
    }

    private func normalize(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
