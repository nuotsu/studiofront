import Foundation
import SanityKit
import StudioStore

/// Fires live, debounced document-title searches against Sanity while the
/// user is actively typing in the popover's search field — the deliberate
/// exception to search otherwise never calling the network (§9.2). Modeled
/// on `PresenceCoordinator`: same per-project `Task` lifecycle, same
/// concurrency-capped fan-out. In-flight work stops while the popover is
/// closed; live matches and the session cache are kept so reopen with the
/// same query still shows mixed project + document rows.
@MainActor
final class DocumentSearchCoordinator {
    /// Below this length a query is too likely to match everything to be
    /// worth a live fan-out across every eligible project.
    private static let minimumQueryLength = 2
    private static let debounceDelay: Duration = .milliseconds(280)
    /// When many projects are eligible, cap remote GROQ fan-out to the most recently edited.
    private static let remoteSearchCap = 40

    private let store: StudioStore
    private let settings: AppSettings
    private let client: SanityClient

    private var debounceTask: Task<Void, Never>?
    private var generation = 0
    private var sessionCache: [String: [String: [EditedDocument]]] = [:]

    init(store: StudioStore, settings: AppSettings, client: SanityClient = .shared) {
        self.store = store
        self.settings = settings
        self.client = client
    }

    /// Called from `PopoverRootView`'s `.onChange(of: store.query)`.
    func queryDidChange(_ query: String) {
        generation += 1
        let thisGeneration = generation
        debounceTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else {
            store.clearDocumentSearchState()
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceDelay)
            guard !Task.isCancelled, let self, thisGeneration == self.generation else { return }
            await self.runSearch(text: trimmed, generation: thisGeneration)
        }
    }

    /// Called from `popoverWillShow` — restores search for a still-active query
    /// without waiting for debounce (query string did not change, so `onChange`
    /// will not fire). Session-cache hits apply immediately.
    func willShow() {
        let trimmed = store.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else { return }

        generation += 1
        let thisGeneration = generation
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard !Task.isCancelled, let self, thisGeneration == self.generation else { return }
            await self.runSearch(text: trimmed, generation: thisGeneration)
        }
    }

    /// Cancels in-flight search and clears the searching spinner. Keeps
    /// `liveDocumentMatchesByProject` and `sessionCache` so reopening the
    /// popover with the same query still shows mixed project + document rows.
    func willHide() {
        generation += 1
        debounceTask?.cancel()
        debounceTask = nil
        store.setSearchingProjectIDs([])
    }

    private func runSearch(text: String, generation: Int) async {
        guard let token = try? TokenStore.shared.load(), !token.isEmpty else { return }

        if let cached = sessionCache[text] {
            store.applyDocumentSearchBatch(updates: cached, completedProjectIDs: Set(cached.keys))
            return
        }

        store.clearDocumentSearchState()

        let eligibleIDs = store.eligibleProjectIDs()
        guard !eligibleIDs.isEmpty else { return }

        var localUpdates: [String: [EditedDocument]] = [:]
        var remoteIDs: [String] = []
        for id in eligibleIDs {
            guard let row = store.rows.first(where: { $0.id == id }) else { continue }
            remoteIDs.append(id)
            let local = store.cachedDocumentMatches(for: row)
            if !local.isEmpty {
                localUpdates[id] = local
            }
        }

        if remoteIDs.count > Self.remoteSearchCap {
            let capped = Set(store.eligibleProjectIDsForPresence(maxCount: Self.remoteSearchCap))
            remoteIDs = remoteIDs.filter { capped.contains($0) }
        }

        // Paint cached title matches immediately; live GROQ still runs so docs
        // outside the recent-20 cache (or stale since last sync) aren't missed.
        if !localUpdates.isEmpty {
            store.applyDocumentSearchBatch(updates: localUpdates, completedProjectIDs: [])
        }
        store.setSearchingProjectIDs(Set(remoteIDs))

        let cappedOutIDs = Set(eligibleIDs).subtracting(Set(remoteIDs))
        if !cappedOutIDs.isEmpty {
            store.applyDocumentSearchBatch(updates: [:], completedProjectIDs: cappedOutIDs)
        }

        guard !remoteIDs.isEmpty else {
            sessionCache[text] = localUpdates
            return
        }

        let limit = SanityClient.datasetConcurrencyLimit
        let client = self.client
        let preferExternal = settings.studioURLPreference == .external
        var allUpdates = localUpdates

        for start in stride(from: 0, to: remoteIDs.count, by: limit) {
            guard generation == self.generation else { return }
            let slice = Array(remoteIDs[start..<min(start + limit, remoteIDs.count)])
            var batchUpdates: [String: [EditedDocument]] = [:]

            await withTaskGroup(of: (String, [RemoteEditedDocument]).self) { group in
                for id in slice {
                    guard let dataset = primaryDataset(for: id) else { continue }
                    group.addTask {
                        let docs = try? await client.searchDocuments(
                            token: token,
                            projectId: id,
                            dataset: dataset,
                            text: text
                        )
                        return (id, docs ?? [])
                    }
                }
                for await (id, docs) in group {
                    guard generation == self.generation else { continue }
                    let studioURL = store.rows.first(where: { $0.id == id })?.resolvedStudioURL(preferExternal: preferExternal)
                    batchUpdates[id] = docs.map { doc in
                        EditedDocument(
                            id: doc.id,
                            title: doc.title,
                            typeName: doc.typeName,
                            editedAt: doc.updatedAt,
                            deepLinkURL: studioURL.flatMap {
                                ProjectSyncService.editIntentURL(studioURL: $0, documentId: doc.id, typeName: doc.typeName)
                            }
                        )
                    }
                }
            }

            var mergedBatch: [String: [EditedDocument]] = [:]
            for id in slice {
                let local = localUpdates[id] ?? allUpdates[id] ?? []
                let remote = batchUpdates[id] ?? []
                mergedBatch[id] = Self.mergeDocumentMatches(local: local, remote: remote)
            }
            allUpdates.merge(mergedBatch) { _, new in new }
            store.applyDocumentSearchBatch(updates: mergedBatch, completedProjectIDs: Set(slice))
        }

        sessionCache[text] = allUpdates
    }

    /// Unions cached and live matches by canonical document id, preferring the
    /// newer entry when draft/published refer to the same doc. Empty remote
    /// results keep local-only hits (e.g. acronym matches).
    private static func mergeDocumentMatches(local: [EditedDocument], remote: [EditedDocument]) -> [EditedDocument] {
        guard !remote.isEmpty else { return local }
        func canonicalId(_ id: String) -> String {
            let prefix = "drafts."
            return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
        }
        var byCanonical: [String: EditedDocument] = [:]
        for doc in local {
            byCanonical[canonicalId(doc.id)] = doc
        }
        for doc in remote {
            let key = canonicalId(doc.id)
            if let existing = byCanonical[key], existing.editedAt >= doc.editedAt {
                continue
            }
            byCanonical[key] = doc
        }
        return byCanonical.values.sorted { $0.editedAt > $1.editedAt }
    }

    private func primaryDataset(for projectId: String) -> String? {
        guard let row = store.rows.first(where: { $0.id == projectId }) else { return nil }
        return ProjectSyncService.primaryDataset(from: row.project.datasets)
    }
}
