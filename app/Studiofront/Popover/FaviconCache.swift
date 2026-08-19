import AppKit

/// Best-effort favicon fetch for a project's avatar, keyed by host. Never
/// blocks rendering — a miss just leaves the row on its letter/color avatar.
actor FaviconCache {
    static let shared = FaviconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private init() {
        cache.countLimit = 100
    }

    func favicon(forHost host: String) async -> NSImage? {
        let key = host as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let existing = inFlight[host] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            await Self.fetch(host: host)
        }
        inFlight[host] = task
        defer { inFlight[host] = nil }

        guard let image = await task.value else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func fetch(host: String) async -> NSImage? {
        guard let url = URL(string: "https://\(host)/favicon.ico") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                return nil
            }
            return await Task.detached(priority: .utility) {
                NSImage(data: data)
            }.value
        } catch {
            return nil
        }
    }
}
