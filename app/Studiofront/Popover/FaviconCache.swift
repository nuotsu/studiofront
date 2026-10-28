import AppKit

/// Best-effort favicon fetch for a project's avatar, keyed by host. Never
/// blocks rendering — a miss just leaves the row on its letter/color avatar.
actor FaviconCache {
    static let shared = FaviconCache()

    // NSCache is thread-safe; shared between the actor and synchronous row peek.
    nonisolated(unsafe) private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()

    private var inFlight: [String: Task<FetchResult, Never>] = [:]
    /// Hosts that answered without a usable favicon, and when. Rows reappear
    /// on every scroll and popover open, so without this a site with no
    /// `/favicon.ico` is re-requested each time. Transient failures (timeouts,
    /// DNS) are never recorded, so they still retry on the next access.
    private var missingSince: [String: Date] = [:]
    private static let missingRetryInterval: TimeInterval = 30 * 60

    private enum FetchResult: Sendable {
        case image(NSImage)
        /// The server responded, but not with a decodable image.
        case missing
        case failed
    }

    private init() {}

    /// Thread-safe read of a cached favicon without awaiting the actor.
    nonisolated static func peekCached(forHost host: String) -> NSImage? {
        imageCache.object(forKey: host as NSString)
    }

    func favicon(forHost host: String) async -> NSImage? {
        let key = host as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            return cached
        }
        if let since = missingSince[host], Date().timeIntervalSince(since) < Self.missingRetryInterval {
            return nil
        }
        if let existing = inFlight[host] {
            if case let .image(image) = await existing.value { return image }
            return nil
        }

        let task = Task<FetchResult, Never> {
            await Self.fetch(host: host)
        }
        inFlight[host] = task
        defer { inFlight[host] = nil }

        switch await task.value {
        case let .image(image):
            missingSince[host] = nil
            Self.imageCache.setObject(image, forKey: key)
            return image
        case .missing:
            missingSince[host] = Date()
            return nil
        case .failed:
            return nil
        }
    }

    private static func fetch(host: String) async -> FetchResult {
        guard let url = URL(string: "https://\(host)/favicon.ico") else { return .missing }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                return .missing
            }
            let image = await Task.detached(priority: .utility) {
                NSImage(data: data)
            }.value
            return image.map(FetchResult.image) ?? .missing
        } catch {
            return .failed
        }
    }
}
