import AppKit

/// Best-effort favicon fetch for a project's avatar, keyed by host. Never
/// blocks rendering — a miss just leaves the row on its letter/color avatar.
/// MainActor-isolated so NSImage decoding never crosses an actor boundary.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()

    private var cache: [String: NSImage?] = [:]

    private init() {}

    func favicon(forHost host: String) async -> NSImage? {
        if let cached = cache[host] {
            return cached
        }
        let image = await Self.fetch(host: host)
        cache[host] = image
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
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}
