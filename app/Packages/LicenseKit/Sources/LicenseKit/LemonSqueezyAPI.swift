import Foundation

public enum LemonSqueezyAPI {
    public static let baseURL = URL(string: "https://api.lemonsqueezy.com")!

    /// Product-level checkout — Lemon Squeezy shows both variants as a picker
    /// when opened without a variant-specific share link.
    public static let checkoutURL = URL(string: "https://nuotsu.lemonsqueezy.com/checkout/buy/05bb0d2e-8e6d-437f-b5b8-11082bc67df0")!

    /// Prefer a per-variant Share URL from the Lemon Squeezy dashboard when
    /// available; until then both buttons use the product-level checkout.
    public static let monthlyCheckoutURL = checkoutURL
    public static let annualCheckoutURL = checkoutURL
}
