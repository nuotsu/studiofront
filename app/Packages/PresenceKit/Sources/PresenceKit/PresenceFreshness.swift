import Foundation

/// How recent an edit/announcement must be for a user to still count as a live
/// editor. Shared by both providers so the number lives in exactly one place.
public enum PresenceFreshness {
    public static let window: TimeInterval = 120
}
