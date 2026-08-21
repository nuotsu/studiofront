import Foundation

enum LicenseSecretRedactor {
    /// Strip a pasted license key from strings that might reach logs or UI.
    static func redact(_ string: String) -> String {
        let patterns = [
            #"[A-Za-z0-9]{8}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{12}"#,
        ]
        var result = string
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[redacted]")
            }
        }
        return result
    }
}
