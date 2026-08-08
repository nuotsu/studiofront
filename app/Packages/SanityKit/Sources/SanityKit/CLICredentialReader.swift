import Darwin
import Foundation

/// Reads `authToken` from the Sanity CLI config.
///
/// VERIFY: docs + `sanity debug` confirm `~/.config/sanity/config.json` on all
/// platforms, key `authToken`. Sandbox cannot see the real home via
/// `homeDirectoryForCurrentUser` (container path) — use `getpwuid` and a
/// home-relative temporary exception, with a security-scoped bookmark fallback.
public enum CLICredentialReader {
    public static let bookmarkDefaultsKey = "sanity.cliConfigBookmark"

    public static var realHomeDirectory: URL {
        if let passwd = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var defaultConfigURL: URL {
        realHomeDirectory.appending(path: ".config/sanity/config.json", directoryHint: .notDirectory)
    }

    public struct Probe: Sendable, Equatable {
        public var url: URL
        public var isReadable: Bool
        public var hasTokenKey: Bool
    }

    public static func probe(bookmarkData: Data? = UserDefaults.standard.data(forKey: bookmarkDefaultsKey)) -> Probe {
        if let bookmarkData, let url = resolveBookmark(bookmarkData) {
            return probe(url: url, scoped: true)
        }
        return probe(url: defaultConfigURL, scoped: false)
    }

    public static func readAuthToken(
        bookmarkData: Data? = UserDefaults.standard.data(forKey: bookmarkDefaultsKey)
    ) throws -> String {
        if let bookmarkData, let url = resolveBookmark(bookmarkData) {
            return try readAuthToken(from: url, scoped: true)
        }
        return try readAuthToken(from: defaultConfigURL, scoped: false)
    }

    public static func readAuthToken(from url: URL, scoped: Bool) throws -> String {
        let accessed = scoped ? url.startAccessingSecurityScopedResource() : true
        defer {
            if scoped, accessed { url.stopAccessingSecurityScopedResource() }
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw SanityAuthError.cliConfigNotFound
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SanityAuthError.unreadable("Couldn’t read the Sanity CLI config.")
        }
        let token = try extractAuthToken(from: data)
        guard let token, !token.isEmpty else {
            throw SanityAuthError.cliTokenMissing
        }
        return token
    }

    public static func makeBookmark(for url: URL) throws -> Data {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkDefaultsKey)
        return data
    }

    public static func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkDefaultsKey)
    }

    private static func probe(url: URL, scoped: Bool) -> Probe {
        let accessed = scoped ? url.startAccessingSecurityScopedResource() : true
        defer {
            if scoped, accessed { url.stopAccessingSecurityScopedResource() }
        }
        let readable = FileManager.default.isReadableFile(atPath: url.path)
        var hasTokenKey = false
        if readable, let data = try? Data(contentsOf: url) {
            hasTokenKey = (try? extractAuthToken(from: data))?.isEmpty == false
        }
        return Probe(url: url, isReadable: readable, hasTokenKey: hasTokenKey)
    }

    private static func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkDefaultsKey)
        }
        return url
    }

    private static func extractAuthToken(from data: Data) throws -> String? {
        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw SanityAuthError.unreadable("The Sanity CLI config isn’t valid JSON.")
        }
        if let token = object["authToken"] as? String { return token }
        // Legacy CLI auth.json used `token`.
        if let token = object["token"] as? String { return token }
        return nil
    }
}
