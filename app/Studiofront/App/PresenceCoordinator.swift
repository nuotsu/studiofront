import Foundation
import PresenceKit
import SanityKit
import StudioStore

/// Owns the presence provider's lifecycle, kept deliberately separate from
/// `ProjectSyncService` — presence is the least-stable subsystem (§7), and
/// isolating its wiring makes it trivially removable/replaceable.
///
/// Connects only for projects eligible while the popover is open and tears
/// everything down the moment it closes — zero sockets/timers while closed
/// (§1, §7.1).
@MainActor
final class PresenceCoordinator {
    private let store: StudioStore
    private let settings: AppSettings
    private let client: SanityClient

    private var provider: (any PresenceProvider)?
    private var forwardingTasks: [String: Task<Void, Never>] = [:]
    /// Per-project stable display order — see `reorderStably`.
    private var order: [String: [String]] = [:]
    private var isActive = false

    init(store: StudioStore, settings: AppSettings, client: SanityClient = .shared) {
        self.store = store
        self.settings = settings
        self.client = client
    }

    func willShow() {
        isActive = true

        guard settings.presenceMode != .off else {
            provider = nil
            return
        }

        let activity = ActivityPresenceProvider(
            client: client,
            tokenProvider: { [weak self] in await self?.currentToken() },
            datasetProvider: { [weak self] id in await self?.primaryDataset(for: id) },
            rosterProvider: { [weak self] id in await self?.roster(for: id) ?? [] }
        )

        switch settings.presenceMode {
        case .off:
            provider = nil
        case .activityOnly:
            provider = activity
        case .realtime:
            provider = RealtimePresenceProvider(
                client: client,
                fallback: activity,
                tokenProvider: { [weak self] in await self?.currentToken() },
                datasetProvider: { [weak self] id in await self?.primaryDataset(for: id) },
                rosterProvider: { [weak self] id in await self?.roster(for: id) ?? [] }
            )
        }

        refreshEligibleProjects()
    }

    func willHide() {
        isActive = false
        for task in forwardingTasks.values { task.cancel() }
        forwardingTasks.removeAll()
        order.removeAll()
        let outgoing = provider
        provider = nil
        Task { await outgoing?.stopAll() }
    }

    /// Re-scopes the connected/polled set to whatever's currently eligible.
    /// Called on open and whenever `StudioStore.onRowsReplaced` fires — the
    /// only point the eligible set can change while the popover stays open.
    func refreshEligibleProjects() {
        guard isActive, let provider else { return }
        let ids = eligibleProjectIds()

        Task { await provider.start(projectIds: ids) }

        for id in ids where forwardingTasks[id] == nil {
            forwardingTasks[id] = Task { [weak self] in
                for await members in await provider.presence(for: id) {
                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    self.store.setActiveUsers(self.reorderStably(members, forProjectID: id), forProjectID: id)
                }
            }
        }
        for id in Set(forwardingTasks.keys).subtracting(ids) {
            forwardingTasks[id]?.cancel()
            forwardingTasks[id] = nil
            order[id] = nil
            store.setActiveUsers([], forProjectID: id)
        }
    }

    /// Most-recently-active-first: a member who just became active is inserted
    /// ahead of everyone already shown; members who stay active keep their
    /// existing relative order. A member who drops out and later returns is
    /// treated as newly active again, not restored to their old slot — so
    /// `order` only ever needs to remember currently-active ids, nothing more.
    /// Both presence providers derive their emitted lists from a `Set`
    /// internally, which has no stable iteration order — this is the one seam
    /// both pass through, so fixing it here covers both without touching
    /// `PresenceKit`.
    private func reorderStably(_ members: [Member], forProjectID id: String) -> [Member] {
        let byId = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let currentIds = Set(byId.keys)
        let previous = order[id] ?? []
        let stillActive = previous.filter { currentIds.contains($0) }
        let newlyActive = currentIds.subtracting(previous).sorted()
        let updated = newlyActive + stillActive
        order[id] = updated
        return updated.compactMap { byId[$0] }
    }

    /// Same eligibility as `ProjectSyncService.fetchActivity` (visible, not
    /// hidden, not archived). No per-row viewport tracking exists in this
    /// app, and search only narrows this same fixed set — so this already
    /// satisfies "only projects renderable in the open popover" (§7.1).
    private func eligibleProjectIds() -> [String] {
        store.rows
            .filter { !$0.curation.isHidden && !$0.isUnavailable && !$0.project.isArchived }
            .map(\.id)
    }

    private func currentToken() async -> String? {
        try? TokenStore.shared.load()
    }

    private func primaryDataset(for projectId: String) async -> String? {
        guard let row = store.rows.first(where: { $0.id == projectId }) else { return nil }
        return ProjectSyncService.primaryDataset(from: row.project.datasets)
    }

    private func roster(for projectId: String) async -> [Member] {
        store.rows.first(where: { $0.id == projectId })?.project.members ?? []
    }
}
