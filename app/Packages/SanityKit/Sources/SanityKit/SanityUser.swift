import Foundation

public struct SanityUser: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public var name: String
    public var email: String?
    public var profileImageURL: URL?

    public init(id: String, name: String, email: String? = nil, profileImageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.profileImageURL = profileImageURL
    }
}

public enum TokenSource: String, Sendable, Codable, Hashable {
    case cli
    case manual

    public var title: String {
        switch self {
        case .cli: "Sanity CLI"
        case .manual: "Manual token"
        }
    }
}
