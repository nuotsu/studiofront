import Foundation

public enum SecretRedactor {
    /// Strip tokens from strings that might reach logs or UI.
    public static func redact(_ string: String) -> String {
        let patterns = [
            #"sk[A-Za-z0-9_\-\.]{8,}"#,
            #"eyJ[A-Za-z0-9_\-\.]{20,}"#,
            #"(?i)(bearer|token|authorization)[:\s]+[^\s]+"#,
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
