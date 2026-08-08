import Foundation

public struct RemoteProject: Sendable, Identifiable, Equatable {
    public var id: String
    public var displayName: String
    public var studioHost: String?
    public var organizationId: String?
    public var createdAt: Date
    public var color: String?
    public var members: [RemoteMember]
    public var datasets: [RemoteDataset]
}

public struct RemoteMember: Sendable, Identifiable, Equatable {
    public var id: String
    public var role: String?
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
    public var appHost: String
}

struct ProjectDTO: Decodable {
    var id: String
    var displayName: String?
    var studioHost: String?
    var organizationId: String?
    var createdAt: Date?
    var metadata: MetadataDTO?
    var members: [MemberDTO]?

    struct MetadataDTO: Decodable {
        var color: String?
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
            organizationId: organizationId.flatMap { $0.isEmpty ? nil : $0 },
            createdAt: createdAt ?? .distantPast,
            color: metadata?.color,
            members: (members ?? []).map { RemoteMember(id: $0.id, role: $0.role) },
            datasets: []
        )
    }
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
    var title: String?
}
