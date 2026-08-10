import Foundation

public struct RemoteProject: Sendable, Identifiable, Equatable {
    public var id: String
    public var displayName: String
    public var studioHost: String?
    public var externalStudioHost: URL?
    public var organizationId: String?
    public var createdAt: Date
    public var color: String?
    /// From `isDisabledByUser` — confirmed against the live API: this is what
    /// Sanity Manage calls "Archived" (its two archived projects both have
    /// `isDisabledByUser: true` and literally "(Archived)" in their name).
    public var isArchived: Bool
    public var members: [RemoteMember]
    public var datasets: [RemoteDataset]
}

public struct RemoteMember: Sendable, Identifiable, Equatable {
    public var id: String
    public var role: String?
}

/// From `GET /projects/{projectId}/users/{ids}` — a different resource shape
/// than `/users/me` (confirmed against the live API: this one uses `imageUrl`,
/// not `/users/me`'s `profileImage`). Both `displayName` and `imageUrl` are
/// absent for members who haven't set one.
public struct RemoteMemberProfile: Sendable, Identifiable, Equatable {
    public var id: String
    public var displayName: String
    public var imageURL: URL?
}

public struct RemoteDataset: Sendable, Hashable {
    public var name: String
    public var aclMode: String
}

public struct RemoteOrganization: Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
}

public struct RemoteStudioApp: Sendable, Equatable {
    public var projectId: String?
    /// A bare `.sanity.studio` subdomain slug when `isExternal` is false
    /// (`urlType: "internal"`), else a full URL string (`urlType: "external"`)
    /// pointing at wherever the developer embedded their Studio.
    public var appHost: String
    public var isExternal: Bool
}

struct ProjectDTO: Decodable {
    var id: String
    var displayName: String?
    var studioHost: String?
    var organizationId: String?
    var createdAt: Date?
    var metadata: MetadataDTO?
    var members: [MemberDTO]?
    var isDisabledByUser: Bool?

    struct MetadataDTO: Decodable {
        var color: String?
        /// Deprecated by Sanity in favor of `/user-applications`, but still the
        /// only field carrying a project's Studio location when it's embedded on
        /// the developer's own domain rather than deployed to a `.sanity.studio`
        /// subdomain — `/user-applications` returns nothing for those projects.
        var externalStudioHost: String?
    }

    struct MemberDTO: Decodable {
        var id: String
        var role: String?
    }

    func asRemote() -> RemoteProject {
        RemoteProject(
            id: id,
            displayName: displayName ?? id,
            studioHost: studioHost.flatMap { $0.isEmpty ? nil : $0 },
            externalStudioHost: metadata?.externalStudioHost.flatMap { URL(string: $0) },
            organizationId: organizationId.flatMap { $0.isEmpty ? nil : $0 },
            createdAt: createdAt ?? .distantPast,
            color: metadata?.color,
            isArchived: isDisabledByUser ?? false,
            members: (members ?? []).map { RemoteMember(id: $0.id, role: $0.role) },
            datasets: []
        )
    }
}

struct ProjectUserDTO: Decodable {
    var id: String
    var displayName: String?
    var imageUrl: String?
}

struct DatasetDTO: Decodable {
    var name: String
    var aclMode: String?
}

struct OrganizationDTO: Decodable {
    var id: String
    var name: String?
    var displayName: String?
    var title: String?

    var resolvedName: String { name ?? displayName ?? title ?? id }
}

struct UserApplicationDTO: Decodable {
    var projectId: String?
    var appHost: String?
    var urlType: String?
    var title: String?
}

public struct RemoteEditedDocument: Sendable, Equatable {
    public var id: String
    public var typeName: String
    public var title: String
    public var updatedAt: Date

    static func resolving(published: DocumentProjectionDTO?, draft: DocumentProjectionDTO?) -> RemoteEditedDocument? {
        let winner: (doc: DocumentProjectionDTO, isDraft: Bool)?
        switch (published, draft) {
        case let (p?, d?):
            winner = d.updatedAt > p.updatedAt ? (d, true) : (p, false)
        case let (p?, nil):
            winner = (p, false)
        case let (nil, d?):
            winner = (d, true)
        case (nil, nil):
            winner = nil
        }
        guard let winner else { return nil }
        let resolvedTitle = winner.doc.title ?? winner.doc.name ?? winner.doc.id
        return RemoteEditedDocument(
            id: winner.doc.id,
            typeName: winner.doc.type,
            title: winner.isDraft ? "Draft: \(resolvedTitle)" : resolvedTitle,
            updatedAt: winner.doc.updatedAt
        )
    }
}

/// One line of the History API's `/data/history/<dataset>/transactions` NDJSON
/// response. Field names confirmed against Sanity's own
/// `TransactionLogEvent` type (`@sanity/types`), not guessed.
public struct RemoteRecentEdit: Sendable, Equatable {
    public var authorId: String
    public var updatedAt: Date
    public var documentIDs: [String]
}

struct TransactionLogEntryDTO: Decodable, Sendable {
    var author: String
    var timestamp: Date
    var documentIDs: [String]
}

/// A malformed or error line (`{"error": {...}}`) in the transactions NDJSON
/// stream — decoded separately so one bad line doesn't fail the whole batch.
struct TransactionLogErrorDTO: Decodable, Sendable {
    var error: ErrorBody

    struct ErrorBody: Decodable, Sendable {
        var type: String?
        var description: String?
    }
}

/// The Query API's generic response shape (`{"query": ..., "result": [...], "ms": ...}`)
/// for queries whose result is a plain array, rather than `QueryEnvelope`'s
/// fixed `{published, draft}` object shape.
struct ArrayQueryEnvelope<Element: Decodable & Sendable>: Decodable, Sendable {
    var result: [Element]
}

struct QueryEnvelope: Decodable, Sendable {
    var published: DocumentProjectionDTO?
    var draft: DocumentProjectionDTO?

    enum CodingKeys: String, CodingKey { case result }
    enum ResultKeys: String, CodingKey { case published, draft }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let result = try container.decodeIfPresent(ResultContainer.self, forKey: .result) else {
            published = nil
            draft = nil
            return
        }
        published = result.published
        draft = result.draft
    }

    private struct ResultContainer: Decodable {
        var published: DocumentProjectionDTO?
        var draft: DocumentProjectionDTO?
    }
}

/// `{_id, _type}` for a batch of ids — resolves the one thing presence data
/// never carries: a document's schema type, needed to build its edit-intent
/// URL (`SanityAPI` docs' `id=...;type=...` format has no id-only form).
struct DocumentTypeProjectionDTO: Decodable, Sendable {
    var id: String
    var type: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type = "_type"
    }
}

struct DocumentProjectionDTO: Decodable, Sendable {
    var id: String
    var type: String
    var updatedAt: Date
    var title: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type = "_type"
        case updatedAt = "_updatedAt"
        case title
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        title = try? container.decode(String.self, forKey: .title)
        name = try? container.decode(String.self, forKey: .name)
    }
}
