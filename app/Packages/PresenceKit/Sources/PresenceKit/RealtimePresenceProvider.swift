import Foundation
import SanityKit
import StudioStore

/// §7.1's real-time provider. Connects one websocket per visible project to
/// Sanity's presence channel and listens only — it never announces this
/// user's own presence (see `BifurPresenceSocket`'s doc comment for why that
/// invariant matters). Any failure for a given project — auth rejected,
/// unexpected close, decode error — silently and permanently falls back to
/// `ActivityPresenceProvider` for that project only, matching §7.1's contract
/// that presence failures must never surface as an error in the UI.
public actor RealtimePresenceProvider: PresenceProvider {
    public typealias TokenProvider = @Sendable () async -> String?
    public typealias DatasetProvider = @Sendable (String) async -> String?
    public typealias RosterProvider = @Sendable (String) async -> [Member]

    private let client: SanityClient
    private let fallback: ActivityPresenceProvider
    private let tokenProvider: TokenProvider
    private let datasetProvider: DatasetProvider
    private let rosterProvider: RosterProvider
    private let maxConcurrentConnections: Int
    private let connectStagger: Duration
    private let ownSessionId = UUID().uuidString

    private var continuations: [String: AsyncStream<[Member]>.Continuation] = [:]
    private var connections: [String: Task<Void, Never>] = [:]
    /// Per project, the live sessions currently known from the socket: sessionId -> (userId, lastActiveAt).
    /// Keyed by session (not user) because one user can have multiple open tabs/sessions.
    private var sessions: [String: [String: (userId: String, lastActiveAt: Date)]] = [:]
    private var fallbackProjectIds: Set<String> = []
    private var tickerTask: Task<Void, Never>?

    public init(
        client: SanityClient,
        fallback: ActivityPresenceProvider,
        tokenProvider: @escaping TokenProvider,
        datasetProvider: @escaping DatasetProvider,
        rosterProvider: @escaping RosterProvider,
        maxConcurrentConnections: Int = 6,
        connectStagger: Duration = .milliseconds(200)
    ) {
        self.client = client
        self.fallback = fallback
        self.tokenProvider = tokenProvider
        self.datasetProvider = datasetProvider
        self.rosterProvider = rosterProvider
        self.maxConcurrentConnections = maxConcurrentConnections
        self.connectStagger = connectStagger
    }

    public func presence(for projectId: String) async -> AsyncStream<[Member]> {
        AsyncStream { continuation in
            self.attach(continuation, for: projectId)
        }
    }

    public func start(projectIds: [String]) async {
        let desired = Set(projectIds)
        let running = Set(connections.keys)
        let removed = running.subtracting(desired)

        for id in removed {
            connections[id]?.cancel()
            connections[id] = nil
            sessions[id] = nil
            fallbackProjectIds.remove(id)
        }
        if !removed.isEmpty {
            await fallback.start(projectIds: Array(fallbackProjectIds))
        }

        ensureTicker()
        let newIds = Array(desired.subtracting(running))
        for batchStart in stride(from: 0, to: newIds.count, by: maxConcurrentConnections) {
            let batchEnd = min(batchStart + maxConcurrentConnections, newIds.count)
            for id in newIds[batchStart..<batchEnd] {
                connections[id] = Task { [weak self, connectStagger] in
                    try? await Task.sleep(for: connectStagger)
                    await self?.runConnection(for: id)
                }
            }
        }
    }

    public func stopAll() async {
        for task in connections.values { task.cancel() }
        connections.removeAll()
        sessions.removeAll()
        fallbackProjectIds.removeAll()
        tickerTask?.cancel()
        tickerTask = nil
        await fallback.stopAll()
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    private func attach(_ continuation: AsyncStream<[Member]>.Continuation, for projectId: String) {
        continuations[projectId] = continuation
    }

    private func ensureTicker() {
        guard tickerTask == nil else { return }
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self?.pruneStale()
            }
        }
    }

    /// Protects the freshness promise against unclean socket drops that never
    /// send an explicit `disconnect` event (crashed tab, dropped network).
    private func pruneStale() async {
        let cutoff = Date().addingTimeInterval(-PresenceFreshness.window)
        for (projectId, projectSessions) in sessions {
            let fresh = projectSessions.filter { $0.value.lastActiveAt >= cutoff }
            if fresh.count != projectSessions.count {
                sessions[projectId] = fresh
                await emitCurrentMembers(for: projectId)
            }
        }
    }

    private func runConnection(for projectId: String) async {
        guard !Task.isCancelled else { return }
        guard let token = await tokenProvider(), let dataset = await datasetProvider(projectId) else {
            await forwardFallback(for: projectId)
            return
        }

        let socket = BifurPresenceSocket(url: client.socketURL(projectId: projectId, dataset: dataset))
        do {
            let events = try await socket.connect(token: token, sessionId: ownSessionId)
            for try await event in events {
                if Task.isCancelled { break }
                await handle(event, for: projectId)
            }
        } catch {
            // Connect failed or the stream ended/threw mid-flight — either
            // way, fall through to the silent fallback below.
        }
        await socket.close()
        guard !Task.isCancelled else { return }
        await forwardFallback(for: projectId)
    }

    private func handle(_ event: BifurPresenceSocket.WireEvent, for projectId: String) async {
        switch event {
        case .state(let userId, let sessionId, let lastActiveAt):
            var projectSessions = sessions[projectId] ?? [:]
            projectSessions[sessionId] = (userId, lastActiveAt ?? Date())
            sessions[projectId] = projectSessions
        case .disconnect(_, let sessionId):
            sessions[projectId]?[sessionId] = nil
        }
        await emitCurrentMembers(for: projectId)
    }

    private func emitCurrentMembers(for projectId: String) async {
        let userIds = Set((sessions[projectId] ?? [:]).values.map(\.userId))
        guard !userIds.isEmpty else {
            continuations[projectId]?.yield([])
            return
        }
        let roster = await rosterProvider(projectId)
        let byId = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })
        continuations[projectId]?.yield(userIds.map { byId[$0] ?? Member(id: $0, displayName: $0) })
    }

    private func forwardFallback(for projectId: String) async {
        fallbackProjectIds.insert(projectId)
        await fallback.start(projectIds: Array(fallbackProjectIds))
        for await members in await fallback.presence(for: projectId) {
            if Task.isCancelled { break }
            continuations[projectId]?.yield(members)
        }
    }
}
