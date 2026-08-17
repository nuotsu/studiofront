import Foundation

public struct PersistedOrganization: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var isFavorite: Bool

    public init(id: String, name: String, isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.isFavorite = isFavorite
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

public struct PersistedSnapshot: Sendable, Codable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var cachedAt: Date?
    public var projects: [SanityProject]
    public var organizations: [PersistedOrganization]
    /// Project curation (favorites, hidden, nickname, links, sort order),
    /// scoped per Sanity user id — never shared across accounts, even when
    /// two accounts see the same project id.
    public var curationByUser: [String: [ProjectCuration]]
    /// Pinned organization ids, scoped per Sanity user id for the same reason.
    public var organizationFavoritesByUser: [String: Set<String>]
    /// Most recently signed-in user id, used to keep curation/pins resolvable
    /// while `AuthSession.status == .reconnectRequired` (same account, no
    /// live `signedInUser` until the token is revalidated).
    public var lastActiveUserID: String?
    public var etags: [String: String]
    public var activity: [String: ProjectActivity]

    public init(
        schemaVersion: Int = PersistedSnapshot.currentSchemaVersion,
        cachedAt: Date? = nil,
        projects: [SanityProject] = [],
        organizations: [PersistedOrganization] = [],
        curationByUser: [String: [ProjectCuration]] = [:],
        organizationFavoritesByUser: [String: Set<String>] = [:],
        lastActiveUserID: String? = nil,
        etags: [String: String] = [:],
        activity: [String: ProjectActivity] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.cachedAt = cachedAt
        self.projects = projects
        self.organizations = organizations
        self.curationByUser = curationByUser
        self.organizationFavoritesByUser = organizationFavoritesByUser
        self.lastActiveUserID = lastActiveUserID
        self.etags = etags
        self.activity = activity
    }
}

public enum PersistenceStore {
    private static let folderName = "Studiofront"
    private static let fileName = "cache-v1.json"

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: folderName, directoryHint: .isDirectory)
    }

    private static var fileURL: URL {
        directoryURL.appending(path: fileName)
    }

    /// Runs the actual encode/decode/disk I/O off the main actor, and serializes
    /// it so concurrent `save()` calls (e.g. rapid favorite toggles) can't
    /// interleave writes to the same file.
    private actor IO {
        static let shared = IO()

        func load() -> PersistedSnapshot? {
            guard let data = try? Data(contentsOf: PersistenceStore.fileURL) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let snapshot = try? decoder.decode(PersistedSnapshot.self, from: data),
                  snapshot.schemaVersion == PersistedSnapshot.currentSchemaVersion
            else { return nil }
            return snapshot
        }

        func save(_ snapshot: PersistedSnapshot) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: PersistenceStore.directoryURL, withIntermediateDirectories: true)
            try? data.write(to: PersistenceStore.fileURL, options: .atomic)
        }
    }

    public static func load() async -> PersistedSnapshot? {
        await IO.shared.load()
    }

    public static func save(_ snapshot: PersistedSnapshot) {
        Task { await IO.shared.save(snapshot) }
    }
}
