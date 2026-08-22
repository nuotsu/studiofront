import Foundation

public enum LemonSqueezyAPI {
    public static let baseURL = URL(string: "https://api.lemonsqueezy.com")!

    /// Product-level checkout — Lemon Squeezy shows both variants as a picker
    /// when opened without a variant-specific share link.
    public static let checkoutURL = URL(string: "https://nuotsu.lemonsqueezy.com/checkout/buy/fdacb744-1100-4aa1-9f44-deee151cb873")!

    /// Prefer a per-variant Share URL from the Lemon Squeezy dashboard when
    /// available; until then both buttons use the product-level checkout.
    public static let monthlyCheckoutURL = checkoutURL
    public static let annualCheckoutURL = checkoutURL
}
