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
    private static let sessionCacheLimit = 64

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

        let rowByID = Dictionary(uniqueKeysWithValues: store.rows.map { ($0.id, $0) })

        var localUpdates: [String: [EditedDocument]] = [:]
        var remoteIDs: [String] = []
        for id in eligibleIDs {
            guard let row = rowByID[id] else { continue }
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

        // Projects without a dataset have nothing to query; settle them now
        // with their local matches.
        let requests = remoteIDs.compactMap { id in
            primaryDataset(from: rowByID[id]).map { (id: id, dataset: $0) }
        }
        let noDatasetIDs = Set(remoteIDs).subtracting(requests.map(\.id))
        if !noDatasetIDs.isEmpty {
            store.applyDocumentSearchBatch(
                updates: localUpdates.filter { noDatasetIDs.contains($0.key) },
                completedProjectIDs: noDatasetIDs
            )
        }

        guard !requests.isEmpty else {
            cacheResults(localUpdates, for: text)
            return
        }

        let limit = SanityClient.datasetConcurrencyLimit
        let client = self.client
        let preferExternal = settings.studioURLPreference == .external
        var allUpdates = localUpdates
        var pending: [String: [EditedDocument]] = [:]

        func flush() {
            guard !pending.isEmpty else { return }
            allUpdates.merge(pending) { _, new in new }
            store.applyDocumentSearchBatch(updates: pending, completedProjectIDs: Set(pending.keys))
            pending = [:]
        }

        await forEachConcurrently(requests, limit: limit) { request -> (String, [RemoteEditedDocument]) in
            let docs = try? await client.searchDocuments(
                token: token,
                projectId: request.id,
                dataset: request.dataset,
                text: text
            )
            return (request.id, docs ?? [])
        } onResult: { id, docs in
            guard generation == self.generation else { return }
            let studioURL = rowByID[id]?.resolvedStudioURL(preferExternal: preferExternal)
            let remote = docs.map { doc in
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
            pending[id] = Self.mergeDocumentMatches(local: localUpdates[id] ?? [], remote: remote)
            // One store update per `limit` results keeps list rebuilds as
            // coarse as fixed batches, without waiting on the slowest project.
            if pending.count >= limit { flush() }
        }

        guard generation == self.generation else { return }
        flush()
        cacheResults(allUpdates, for: text)
    }

    /// Bounded so a long-running menu bar session can't grow it without limit.
    private func cacheResults(_ results: [String: [EditedDocument]], for text: String) {
        if sessionCache.count >= Self.sessionCacheLimit {
            sessionCache.removeAll()
        }
        sessionCache[text] = results
    }

    /// Drops cached results after a project refresh so a repeated query
    /// can't keep serving documents from before the latest sync.
    func resetSessionCache() {
        sessionCache.removeAll()
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

    private func primaryDataset(from row: ProjectRow?) -> String? {
        guard let row else { return nil }
        return ProjectSyncService.primaryDataset(from: row.project.datasets)
    }
}
