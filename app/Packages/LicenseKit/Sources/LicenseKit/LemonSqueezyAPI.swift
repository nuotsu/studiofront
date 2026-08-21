import Foundation

public enum LemonSqueezyAPI {
    public static let baseURL = URL(string: "https://api.lemonsqueezy.com")!

    /// One product-level checkout — Lemon Squeezy shows both variants
    /// (Monthly/Annual) as a picker on the hosted checkout page itself, so a
    /// single link covers both plans.
    public static let checkoutURL = URL(string: "https://nuotsu.lemonsqueezy.com/checkout/buy/fdacb744-1100-4aa1-9f44-deee151cb873")!
}
