import Foundation
import SanityKit
import StudioStore

/// Fires live, debounced document-title searches against Sanity while the
/// user is actively typing in the popover's search field — the deliberate
/// exception to search otherwise never calling the network (§9.2). Modeled
/// on `PresenceCoordinator`: same per-project `Task` lifecycle, same
/// concurrency-capped fan-out, same "only while the popover is open, zero
/// background work while closed" discipline.
@MainActor
final class DocumentSearchCoordinator {
    /// Below this length a query is too likely to match everything to be
    /// worth a live fan-out across every eligible project.
    private static let minimumQueryLength = 2
    private static let debounceDelay: Duration = .milliseconds(280)

    private let store: StudioStore
    private let settings: AppSettings
    private let client: SanityClient

    private var debounceTask: Task<Void, Never>?
    private var generation = 0

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
            store.liveDocumentMatchesByProject = [:]
            store.searchingProjectIDs = []
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceDelay)
            guard !Task.isCancelled, let self, thisGeneration == self.generation else { return }
            await self.runSearch(text: trimmed, generation: thisGeneration)
        }
    }

    /// Mirrors `PresenceCoordinator.willHide()` — cancels everything and
    /// clears live state so nothing lingers or fires once the popover (and
    /// with it, the search field) is gone.
    func willHide() {
        generation += 1
        debounceTask?.cancel()
        debounceTask = nil
        store.liveDocumentMatchesByProject = [:]
        store.searchingProjectIDs = []
    }

    private func runSearch(text: String, generation: Int) async {
        guard let token = try? TokenStore.shared.load(), !token.isEmpty else { return }
        let ids = eligibleProjectIds()
        guard !ids.isEmpty else { return }

        store.liveDocumentMatchesByProject = [:]
        store.searchingProjectIDs = Set(ids)

        let limit = SanityClient.datasetConcurrencyLimit
        let client = self.client
        let preferExternal = settings.studioURLPreference == .external
        for start in stride(from: 0, to: ids.count, by: limit) {
            guard generation == self.generation else { return }
            let slice = Array(ids[start..<min(start + limit, ids.count)])
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
                    store.liveDocumentMatchesByProject[id] = docs.map { doc in
                        EditedDocument(
                            title: doc.title,
                            typeName: doc.typeName,
                            editedAt: doc.updatedAt,
                            deepLinkURL: studioURL.flatMap {
                                ProjectSyncService.editIntentURL(studioURL: $0, documentId: doc.id, typeName: doc.typeName)
                            }
                        )
                    }
                    store.searchingProjectIDs.remove(id)
                }
            }
        }
    }

    /// Same eligibility `PresenceCoordinator`/`ProjectSyncService.fetchActivity`
    /// use: visible, not hidden, not archived.
    private func eligibleProjectIds() -> [String] {
        store.rows
            .filter { !$0.curation.isHidden && !$0.isUnavailable && !$0.project.isArchived }
            .map(\.id)
    }

    private func primaryDataset(for projectId: String) -> String? {
        guard let row = store.rows.first(where: { $0.id == projectId }) else { return nil }
        return ProjectSyncService.primaryDataset(from: row.project.datasets)
    }
}
