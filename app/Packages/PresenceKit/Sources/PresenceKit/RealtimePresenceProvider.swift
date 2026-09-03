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
    /// Per project, the live sessions currently known from the socket: sessionId -> (userId, lastActiveAt, documentId).
    /// Keyed by session (not user) because one user can have multiple open tabs/sessions.
    private var sessions: [String: [String: (userId: String, lastActiveAt: Date, documentId: String?)]] = [:]
    /// Last emitted visible roster fingerprint per project — `(userId, documentId)`
    /// pairs. `state` pings that only refresh `lastActiveAt` skip a yield.
    private var lastEmittedRoster: [String: Set<RosterKey>] = [:]
    private var fallbackProjectIds: Set<String> = []
    private var tickerTask: Task<Void, Never>?

    private struct RosterKey: Hashable {
        var userId: String
        var documentId: String?
    }

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
            continuation.onTermination = { [weak self] _ in
                Task { await self?.detach(projectId) }
            }
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
            lastEmittedRoster[id] = nil
            fallbackProjectIds.remove(id)
            continuations[id]?.finish()
            continuations[id] = nil
        }
        if !removed.isEmpty {
            await fallback.start(projectIds: Array(fallbackProjectIds))
        }

        ensureTicker()
        let newIds = Array(desired.subtracting(running))
        for (index, id) in newIds.enumerated() {
            let batchIndex = index / maxConcurrentConnections
            connections[id] = Task { [weak self, connectStagger] in
                if batchIndex > 0 {
                    try? await Task.sleep(for: connectStagger * Double(batchIndex))
                }
                await self?.runConnection(for: id)
            }
        }
    }

    public func stopAll() async {
        for task in connections.values { task.cancel() }
        connections.removeAll()
        sessions.removeAll()
        lastEmittedRoster.removeAll()
        fallbackProjectIds.removeAll()
        tickerTask?.cancel()
        tickerTask = nil
        await fallback.stopAll()
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    private func attach(_ continuation: AsyncStream<[Member]>.Continuation, for projectId: String) {
        // Finish any prior continuation for this project before replacing it —
        // otherwise its consumer's `for await` loop would hang forever, waiting
        // on a stream that will never receive another value or terminate.
        continuations[projectId]?.finish()
        continuations[projectId] = continuation
        // PresenceCoordinator starts sockets and consumer streams concurrently,
        // so rollcall can land before this continuation is attached. Yield the
        // current set immediately (empty if nobody is connected yet).
        Task { await self.emitCurrentMembers(for: projectId) }
    }

    private func detach(_ projectId: String) {
        continuations[projectId] = nil
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
        var rosterChanged = false
        switch event {
        case .state(let userId, let sessionId, let lastActiveAt, let documentId):
            var projectSessions = sessions[projectId] ?? [:]
            let previous = projectSessions[sessionId]
            projectSessions[sessionId] = (userId, lastActiveAt ?? Date(), documentId)
            sessions[projectId] = projectSessions
            // Keep lastActiveAt for stale pruning, but only emit when the
            // visible (userId, documentId) pair for this session changes.
            if previous?.userId != userId || previous?.documentId != documentId {
                rosterChanged = true
            } else if previous == nil {
                rosterChanged = true
            }
        case .disconnect(_, let sessionId):
            if sessions[projectId]?[sessionId] != nil {
                sessions[projectId]?[sessionId] = nil
                rosterChanged = true
            }
        }
        if rosterChanged {
            await emitCurrentMembers(for: projectId)
        }
    }

    private func emitCurrentMembers(for projectId: String) async {
        let projectSessions = sessions[projectId] ?? [:]
        guard !projectSessions.isEmpty else {
            let alreadyEmpty = lastEmittedRoster[projectId]?.isEmpty == true
            if !alreadyEmpty {
                lastEmittedRoster[projectId] = []
                continuations[projectId]?.yield([])
            }
            return
        }
        // One user can have several open sessions (tabs) — surface the
        // document from whichever session was active most recently.
        var mostRecentByUser: [String: (lastActiveAt: Date, documentId: String?)] = [:]
        for session in projectSessions.values {
            if let existing = mostRecentByUser[session.userId], existing.lastActiveAt >= session.lastActiveAt {
                continue
            }
            mostRecentByUser[session.userId] = (session.lastActiveAt, session.documentId)
        }
        let fingerprint = Set(mostRecentByUser.map { RosterKey(userId: $0.key, documentId: $0.value.documentId) })
        if lastEmittedRoster[projectId] == fingerprint { return }
        lastEmittedRoster[projectId] = fingerprint

        let roster = await rosterProvider(projectId)
        let byId = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })
        continuations[projectId]?.yield(mostRecentByUser.map { userId, info in
            var member = byId[userId] ?? Member(id: userId, displayName: "")
            member.currentDocumentId = info.documentId
            return member
        })
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
