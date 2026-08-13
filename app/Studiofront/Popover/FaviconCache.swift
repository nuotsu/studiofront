import AppKit

/// Best-effort favicon fetch for a project's avatar, keyed by host. Never
/// blocks rendering — a miss just leaves the row on its letter/color avatar.
/// MainActor-isolated so NSImage decoding never crosses an actor boundary.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()

    // NSCache rather than a plain dictionary: bounds memory automatically under
    // pressure, and — crucially — only ever holds successful fetches, so a
    // transient failure (timeout, DNS hiccup) doesn't permanently disable a
    // project's favicon for the rest of the process lifetime.
    private let cache = NSCache<NSString, NSImage>()

    private init() {}

    func favicon(forHost host: String) async -> NSImage? {
        let key = host as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = await Self.fetch(host: host) else { return nil }
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
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}
