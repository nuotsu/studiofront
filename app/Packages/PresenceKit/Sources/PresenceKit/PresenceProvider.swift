import Foundation
import StudioStore

/// A source of "who's live-editing right now" for a set of projects.
///
/// Implementations never throw and never surface an error to callers — any
/// failure degrades silently (§7.1). Streams returned by `presence(for:)` are
/// already filtered to `PresenceFreshness.window`; callers render whatever is
/// emitted without doing their own staleness math.
public protocol PresenceProvider: Sendable {
    /// A stream of the currently-live member set for one project. Emits an
    /// empty array (never an error) when nobody is present or the provider
    /// couldn't determine anything.
    func presence(for projectId: String) async -> AsyncStream<[Member]>

    /// The full desired set of connected/polled project ids. Implementations
    /// diff against what's currently active and connect/disconnect only the
    /// delta — callers may call this repeatedly as the eligible set changes.
    func start(projectIds: [String]) async

    /// Tears down every connection/poll. After this returns, zero sockets and
    /// zero timers remain — required while the popover is closed (§1, §7.1).
    func stopAll() async
}
