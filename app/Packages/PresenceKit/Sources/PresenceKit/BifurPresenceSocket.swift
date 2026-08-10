import Foundation

/// One websocket connection to Sanity's presence channel, speaking the same
/// JSON-RPC 2.0 protocol Sanity Studio itself uses (`@sanity/bifur-client`).
///
/// Read-only by design: this type sends `authorization`, `presence_subscribe`,
/// and one `presence_rollcall` to request a snapshot — and nothing else.
/// It must never send `presence_announce` or `presence_disconnect`, which
/// would report this user's own presence to their teammates (§7.1's veto
/// condition). That is a hard invariant, not a tuning choice.
actor BifurPresenceSocket {
    enum WireEvent: Sendable {
        case state(userId: String, sessionId: String, lastActiveAt: Date?)
        case disconnect(userId: String, sessionId: String)
    }

    enum SocketError: Error, Sendable {
        case timedOut
        case rejected
        case closed
    }

    private let url: URL
    private let urlSession: URLSession
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var subscriptionId: String?
    private var eventContinuation: AsyncThrowingStream<WireEvent, Error>.Continuation?
    private var authContinuations: [String: CheckedContinuation<Void, Error>] = [:]
    private var subscribeContinuations: [String: CheckedContinuation<String, Error>] = [:]
    private var requestCounter = 0

    init(url: URL, urlSession: URLSession = .shared) {
        self.url = url
        self.urlSession = urlSession
    }

    func connect(
        token: String,
        sessionId: String,
        timeout: Duration = .seconds(8)
    ) async throws -> AsyncThrowingStream<WireEvent, Error> {
        let task = urlSession.webSocketTask(with: url)
        socketTask = task
        task.resume()
        receiveTask = Task { [weak self] in await self?.receiveLoop() }

        let stream = AsyncThrowingStream<WireEvent, Error> { continuation in
            self.setEventContinuation(continuation)
        }

        try await withThrowingTimeout(timeout) { try await self.authorize(token: token) }
        let subscriptionId = try await withThrowingTimeout(timeout) { try await self.subscribeToPresence() }
        self.subscriptionId = subscriptionId
        await send(method: "presence_rollcall", params: ["session": sessionId], id: nextRequestId())

        return stream
    }

    func close() {
        receiveTask?.cancel()
        receiveTask = nil
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
        eventContinuation?.finish()
        eventContinuation = nil
        failAllPending(with: SocketError.closed)
    }

    // MARK: - Handshake

    private func authorize(token: String) async throws {
        let id = nextRequestId()
        try await withCheckedThrowingContinuation { continuation in
            authContinuations[id] = continuation
            Task { await self.send(method: "authorization", params: ["authorization": "Bearer \(token)"], id: id) }
        }
    }

    private func subscribeToPresence() async throws -> String {
        let id = nextRequestId()
        return try await withCheckedThrowingContinuation { continuation in
            subscribeContinuations[id] = continuation
            Task { await self.send(method: "presence_subscribe", params: [:], id: id) }
        }
    }

    private func setEventContinuation(_ continuation: AsyncThrowingStream<WireEvent, Error>.Continuation) {
        eventContinuation = continuation
    }

    private func nextRequestId() -> String {
        requestCounter += 1
        return "sf-\(requestCounter)-\(UUID().uuidString.prefix(8))"
    }

    // MARK: - Wire I/O

    private func send(method: String, params: [String: Any], id: String) async {
        var payload = params
        payload["apiVersion"] = "v1"
        let message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await socketTask?.send(.string(text))
    }

    private func receiveLoop() async {
        guard let socketTask else { return }
        while !Task.isCancelled {
            do {
                let message = try await socketTask.receive()
                switch message {
                case .string(let text):
                    handleIncoming(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleIncoming(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                failAllPending(with: error)
                eventContinuation?.finish(throwing: error)
                return
            }
        }
    }

    /// Heartbeat frames are the bare text `"♥"`, not JSON — handled first so
    /// they never hit a decode attempt.
    private func handleIncoming(_ text: String) {
        guard text != "♥", let data = text.data(using: .utf8) else { return }

        if let push = try? Self.decoder.decode(SubscriptionPushDTO.self, from: data),
           push.subscriptionId == subscriptionId
        {
            switch push.event.type {
            case "state":
                if let userId = push.event.userId, let sessionId = push.event.sessionId {
                    eventContinuation?.yield(.state(userId: userId, sessionId: sessionId, lastActiveAt: push.event.lastActiveAt))
                }
            case "disconnect":
                if let userId = push.event.userId, let sessionId = push.event.sessionId {
                    eventContinuation?.yield(.disconnect(userId: userId, sessionId: sessionId))
                }
            default:
                // "rollCall" from another client — we never respond, since
                // responding would mean announcing our own presence.
                break
            }
            return
        }

        if let response = try? Self.decoder.decode(RPCResponseProbeDTO.self, from: data) {
            resolveResponse(id: response.id, hasError: response.error != nil, resultString: response.resultString)
        }
    }

    private func resolveResponse(id: String, hasError: Bool, resultString: String?) {
        if let continuation = authContinuations.removeValue(forKey: id) {
            hasError ? continuation.resume(throwing: SocketError.rejected) : continuation.resume()
            return
        }
        if let continuation = subscribeContinuations.removeValue(forKey: id) {
            if !hasError, let resultString {
                continuation.resume(returning: resultString)
            } else {
                continuation.resume(throwing: SocketError.rejected)
            }
        }
        // Otherwise this is the response to a fire-and-forget request
        // (presence_rollcall) — nothing to resolve.
    }

    private func failAllPending(with error: Error) {
        for continuation in authContinuations.values { continuation.resume(throwing: error) }
        authContinuations.removeAll()
        for continuation in subscribeContinuations.values { continuation.resume(throwing: error) }
        subscribeContinuations.removeAll()
    }

    // MARK: - Wire types

    /// Field names confirmed against Sanity Studio's own presence client
    /// source (`bifurTransport.ts`'s `IncomingBifurEvent` and
    /// `presence-store.ts`'s `PresenceLocation`), not guessed.
    private struct PresenceWireEventDTO: Decodable {
        var type: String
        var userId: String?
        var sessionId: String?
        var lastActiveAt: Date?

        private enum CodingKeys: String, CodingKey {
            case type, i, session, m
        }
        private enum MKeys: String, CodingKey {
            case sessionId, session, locations
        }
        private struct LocationDTO: Decodable {
            var lastActiveAt: Date?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            userId = try? container.decode(String.self, forKey: .i)
            if let m = try? container.nestedContainer(keyedBy: MKeys.self, forKey: .m) {
                sessionId = (try? m.decode(String.self, forKey: .sessionId)) ?? (try? m.decode(String.self, forKey: .session))
                if let locations = try? m.decode([LocationDTO].self, forKey: .locations) {
                    lastActiveAt = locations.compactMap(\.lastActiveAt).max()
                }
            } else {
                sessionId = try? container.decode(String.self, forKey: .session)
            }
        }
    }

    private struct SubscriptionPushDTO: Decodable {
        var subscriptionId: String
        var event: PresenceWireEventDTO

        private enum CodingKeys: String, CodingKey { case method, params }
        private enum ParamsKeys: String, CodingKey { case subscription, result }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let method = try container.decode(String.self, forKey: .method)
            guard method == "presence_subscription" else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a subscription push"))
            }
            let params = try container.nestedContainer(keyedBy: ParamsKeys.self, forKey: .params)
            subscriptionId = try params.decode(String.self, forKey: .subscription)
            event = try params.decode(PresenceWireEventDTO.self, forKey: .result)
        }
    }

    private struct RPCResponseProbeDTO: Decodable {
        var id: String
        var error: RPCErrorDTO?
        var resultString: String?

        private enum CodingKeys: String, CodingKey { case id, error, result }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            error = try? container.decodeIfPresent(RPCErrorDTO.self, forKey: .error)
            resultString = try? container.decodeIfPresent(String.self, forKey: .result)
        }
    }

    private struct RPCErrorDTO: Decodable {
        var code: Int?
        var message: String?
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle()) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
        }
        return decoder
    }()
}

private func withThrowingTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw BifurPresenceSocket.SocketError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw BifurPresenceSocket.SocketError.timedOut
        }
        return result
    }
}
