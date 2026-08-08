import Foundation

/// Pinned Management API version. VERIFY: documented on OAuth + users/me as `v2021-06-07`.
public enum SanityAPI {
    public static let version = "v2021-06-07"
    /// `/user-applications` returns `501 Not Implemented` below `v2024-08-01` —
    /// confirmed directly against the live API, not from docs alone.
    public static let userApplicationsVersion = "v2024-08-01"
    public static let baseURL = URL(string: "https://api.sanity.io")!
}
