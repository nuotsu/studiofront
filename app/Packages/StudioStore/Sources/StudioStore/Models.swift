import Foundation

public struct SanityProject: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public var displayName: String
    public var organizationId: String?
    public var organizationName: String?
    public var studioHost: String?
    /// From the (deprecated but still populated) `metadata.externalStudioHost`
    /// project field — where the Studio is embedded on the developer's own
    /// domain instead of a `.sanity.studio` subdomain.
    public var externalStudioHost: URL?
    public var datasets: [Dataset]
    public var members: [Member]
    public var currentUserRole: String?
    public var createdAt: Date
    /// Fixture / favicon stand-in. Nil → initials on the theme tag background.
    public var brandColorHex: String?
    /// From `isDisabledByUser` — Sanity Manage's "Archived" state.
    public var isArchived: Bool

    public init(
        id: String,
        displayName: String,
        organizationId: String? = nil,
        organizationName: String? = nil,
        studioHost: String? = nil,
        externalStudioHost: URL? = nil,
        datasets: [Dataset] = [],
        members: [Member] = [],
        currentUserRole: String? = nil,
        createdAt: Date = Date(),
        brandColorHex: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.studioHost = studioHost
        self.externalStudioHost = externalStudioHost
        self.datasets = datasets
        self.members = members
        self.currentUserRole = currentUserRole
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.brandColorHex = brandColorHex
    }

    /// Where the "Studio" button — and any deep link into a specific document —
    /// should actually go: a deployed `.sanity.studio` subdomain first, then the
    /// project's own domain if the Studio is embedded there (`externalStudioHost`),
    /// else the Manage page as last resort.
    public var resolvedStudioURL: URL? {
        if let studioHost, !studioHost.isEmpty,
           let url = URL(string: "https://\(studioHost).sanity.studio")
        {
            return url
        }
        return externalStudioHost ?? manageURL
    }

    public var manageURL: URL? {
        URL(string: "https://www.sanity.io/manage/project/\(id)")
    }
}

public struct Dataset: Sendable, Hashable, Codable {
    public let name: String
    public let aclMode: String

    public init(name: String, aclMode: String = "public") {
        self.name = name
        self.aclMode = aclMode
    }
}

public struct Member: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public var displayName: String
    public var imageURL: URL?
    public var initials: String
    public var role: String?
    /// The document this member is currently on, from presence data — set
    /// only by the presence pipeline (`PresenceProvider` implementations),
    /// never by roster-building. Raw, pre-resolution: no schema type is
    /// known yet, so it isn't openable on its own. See `deepLinkURL`.
    public var currentDocumentId: String?
    /// Resolved from `currentDocumentId` once its schema type is known —
    /// see `PresenceCoordinator`. `nil` until resolved, or if there's no
    /// current document.
    public var deepLinkURL: URL?

    public init(
        id: String,
        displayName: String,
        imageURL: URL? = nil,
        initials: String? = nil,
        role: String? = nil,
        currentDocumentId: String? = nil,
        deepLinkURL: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.imageURL = imageURL
        self.role = role
        self.currentDocumentId = currentDocumentId
        self.deepLinkURL = deepLinkURL
        if let initials {
            self.initials = initials
        } else {
            self.initials = Member.initials(from: displayName)
        }
    }

    public static func initials(from name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

public struct NamedLink: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var label: String
    public var url: URL

    public init(id: UUID = UUID(), label: String, url: URL) {
        self.id = id
        self.label = label
        self.url = url
    }
}

public struct ProjectCuration: Sendable, Codable, Hashable {
    public let projectId: String
    public var isFavorite: Bool
    public var isHidden: Bool
    public var manualSortIndex: Int?
    public var nickname: String?
    public var frontendLinks: [NamedLink]
    public var extraStudioLinks: [NamedLink]

    public init(
        projectId: String,
        isFavorite: Bool = false,
        isHidden: Bool = false,
        manualSortIndex: Int? = nil,
        nickname: String? = nil,
        frontendLinks: [NamedLink] = [],
        extraStudioLinks: [NamedLink] = []
    ) {
        self.projectId = projectId
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.manualSortIndex = manualSortIndex
        self.nickname = nickname
        self.frontendLinks = frontendLinks
        self.extraStudioLinks = extraStudioLinks
    }

    public var primaryFrontendURL: URL? {
        frontendLinks.first?.url
    }
}

public struct EditedDocument: Sendable, Hashable, Codable {
    public var title: String
    public var typeName: String
    public var editedAt: Date
    public var deepLinkURL: URL?

    public init(title: String, typeName: String, editedAt: Date, deepLinkURL: URL? = nil) {
        self.title = title
        self.typeName = typeName
        self.editedAt = editedAt
        self.deepLinkURL = deepLinkURL
    }
}

public struct ProjectActivity: Sendable, Hashable, Codable {
    public var lastDeployedAt: Date?
    public var lastEditedDocument: EditedDocument?
    public var activeUsers: [Member]

    public init(
        lastDeployedAt: Date? = nil,
        lastEditedDocument: EditedDocument? = nil,
        activeUsers: [Member] = []
    ) {
        self.lastDeployedAt = lastDeployedAt
        self.lastEditedDocument = lastEditedDocument
        self.activeUsers = activeUsers
    }
}

public struct ProjectRow: Sendable, Identifiable, Hashable {
    public var id: String { project.id }
    public var project: SanityProject
    public var curation: ProjectCuration
    public var activity: ProjectActivity
    public var isUnavailable: Bool

    public init(
        project: SanityProject,
        curation: ProjectCuration,
        activity: ProjectActivity,
        isUnavailable: Bool = false
    ) {
        self.project = project
        self.curation = curation
        self.activity = activity
        self.isUnavailable = isUnavailable
    }

    public var displayTitle: String {
        curation.nickname ?? project.displayName
    }

    public var resolvedStudioURL: URL? { project.resolvedStudioURL }
}

public enum GroupBy: String, CaseIterable, Identifiable, Sendable {
    case organization
    case lastEdited

    public var id: Self { self }

    public var title: String {
        switch self {
        case .organization: "Org"
        case .lastEdited: "Last edited"
        }
    }
}

public enum RecencyBucket: String, CaseIterable, Sendable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case earlier

    public var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .earlier: "Earlier"
        }
    }

    public static func bucket(for date: Date, now: Date = Date()) -> RecencyBucket {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return .yesterday
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return .thisWeek
        }
        if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
           calendar.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear)
        {
            return .lastWeek
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return .thisMonth
        }
        if let lastMonth = calendar.date(byAdding: .month, value: -1, to: now),
           calendar.isDate(date, equalTo: lastMonth, toGranularity: .month)
        {
            return .lastMonth
        }
        return .earlier
    }
}

public struct OrganizationRecord: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var isFavorite: Bool

    public init(id: String, name: String, isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.isFavorite = isFavorite
    }
}

public struct ProjectGroup: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var organizationId: String?
    public var items: [ProjectRow]

    public init(id: String, title: String, organizationId: String? = nil, items: [ProjectRow]) {
        self.id = id
        self.title = title
        self.organizationId = organizationId
        self.items = items
    }
}
