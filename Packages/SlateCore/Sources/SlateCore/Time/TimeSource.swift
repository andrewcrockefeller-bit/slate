import Foundation

/// Supplies the current moment to domain logic.
///
/// Layer 1 never calls `Date()`. The tutor loop is defined almost entirely in
/// terms of elapsed time — stall thresholds, hint cooldowns, quiet periods,
/// dwell detection — and testing any of that against the real clock means
/// either sleeping in tests or accepting flakiness. Both are worse than one
/// injected protocol.
///
/// Deliberately not named `Clock`: the Swift standard library already defines a
/// `Clock` protocol, and shadowing it in a module people will import alongside
/// Foundation invites confusing diagnostics.
public protocol TimeSource: Sendable {
    /// The current moment.
    var now: Date { get }
}

extension TimeSource {
    /// Seconds elapsed since `moment`, never negative.
    ///
    /// Clamped at zero because a timestamp in the future is a symptom of clock
    /// adjustment or a synced device, and every caller in the tutor loop treats
    /// "negative elapsed time" as nonsense. Failing closed to zero means a
    /// clock change delays a hint; failing open would fire every trigger at
    /// once.
    public func elapsed(since moment: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(moment))
    }

    /// Whether at least `interval` has passed since `moment`.
    public func hasElapsed(_ interval: TimeInterval, since moment: Date) -> Bool {
        elapsed(since: moment) >= interval
    }
}

/// A time source pinned to one moment, for tests and deterministic rendering.
///
/// Immutable by design. A fake that advances belongs in the test target, where
/// it can be mutable without making a shared value type unsafe to pass across
/// isolation boundaries.
public struct FixedTimeSource: TimeSource {
    public let now: Date

    public init(now: Date) {
        self.now = now
    }

    /// A stable, arbitrary reference moment for tests that only care about
    /// relative time. 2026-01-01T00:00:00Z.
    public static let reference = FixedTimeSource(
        now: Date(timeIntervalSince1970: 1_767_225_600)
    )
}
