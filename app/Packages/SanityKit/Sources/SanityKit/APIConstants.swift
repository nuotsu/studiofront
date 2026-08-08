import Foundation

/// Pinned Management API version. VERIFY: documented on OAuth + users/me as `v2021-06-07`.
public enum SanityAPI {
    public static let version = "v2021-06-07"
    public static let baseURL = URL(string: "https://api.sanity.io")!
}
