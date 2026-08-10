import Foundation
import SanityKit
import StudioStore

/// §7.2's fallback provider — derives "recently active" from the documented
/// History API's transactions endpoint rather than a live presence channel.
/// Always works; the tradeoff is honestly a few-minute lag, not a live feed.
public actor ActivityPresenceProvider: PresenceProvider {
    public typealias TokenProvider = @Sendable () async -> String?
    public typealias DatasetProvider = @Sendable (String) async -> String?
    public typealias RosterProvider = @Sendable (String) async -> [Member]

    private let client: SanityClient
    private let pollInterval: TimeInterval
    private let tokenProvider: TokenProvider
    private let datasetProvider: DatasetProvider
    private let rosterProvider: RosterProvider

    private var continuations: [String: AsyncStream<[Member]>.Continuation] = [:]
    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var lastKnownMembers: [String: [Member]] = [:]

    public init(
        client: SanityClient,
        pollInterval: TimeInterval = 90,
        tokenProvider: @escaping TokenProvider,
        datasetProvider: @escaping DatasetProvider,
        rosterProvider: @escaping RosterProvider
    ) {
        self.client = client
        self.pollInterval = pollInterval
        self.tokenProvider = tokenProvider
        self.datasetProvider = datasetProvider
        self.rosterProvider = rosterProvider
    }

    public func presence(for projectId: String) async -> AsyncStream<[Member]> {
        AsyncStream { continuation in
            self.attach(continuation, for: projectId)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.detach(projectId) }
            }
        }
    }

    public func start(projectIds: [String]) async {
        let desired = Set(projectIds)
        let running = Set(pollTasks.keys)

        for id in running.subtracting(desired) {
            pollTasks[id]?.cancel()
            pollTasks[id] = nil
        }
        for id in desired.subtracting(running) {
            pollTasks[id] = Task { [weak self] in
                await self?.pollLoop(for: id)
            }
        }
    }

    public func stopAll() async {
        for task in pollTasks.values { task.cancel() }
        pollTasks.removeAll()
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
        lastKnownMembers.removeAll()
    }

    private func attach(_ continuation: AsyncStream<[Member]>.Continuation, for projectId: String) {
        continuations[projectId] = continuation
        if let cached = lastKnownMembers[projectId] {
            continuation.yield(cached)
        }
    }

    private func detach(_ projectId: String) {
        continuations[projectId] = nil
    }

    private func pollLoop(for projectId: String) async {
        while !Task.isCancelled {
            await pollOnce(for: projectId)
            try? await Task.sleep(for: .seconds(pollInterval))
        }
    }

    /// The History API's `fromTime` filter makes every result correct by
    /// construction — an author who stops editing simply drops out of the
    /// next poll's response, so no client-side pruning is needed.
    private func pollOnce(for projectId: String) async {
        guard let token = await tokenProvider(), let dataset = await datasetProvider(projectId) else {
            emit([], for: projectId)
            return
        }
        let since = Date().addingTimeInterval(-PresenceFreshness.window)
        do {
            let edits = try await client.recentEditors(
                token: token,
                projectId: projectId,
                dataset: dataset,
                since: since
            )
            // One author can appear in several transactions within the window —
            // surface the document from whichever was most recent.
            var mostRecentByAuthor: [String: RemoteRecentEdit] = [:]
            for edit in edits {
                if let existing = mostRecentByAuthor[edit.authorId], existing.updatedAt >= edit.updatedAt {
                    continue
                }
                mostRecentByAuthor[edit.authorId] = edit
            }
            guard !mostRecentByAuthor.isEmpty else {
                emit([], for: projectId)
                return
            }
            let roster = await rosterProvider(projectId)
            let byId = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })
            emit(mostRecentByAuthor.map { authorId, edit in
                var member = byId[authorId] ?? Member(id: authorId, displayName: "")
                member.currentDocumentId = edit.documentIDs.first
                return member
            }, for: projectId)
        } catch {
            emit([], for: projectId)
        }
    }

    private func emit(_ members: [Member], for projectId: String) {
        lastKnownMembers[projectId] = members
        continuations[projectId]?.yield(members)
    }
}
