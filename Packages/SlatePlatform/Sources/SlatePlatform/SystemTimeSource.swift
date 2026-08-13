import Foundation
import SlateCore

/// The real clock.
///
/// The entire body of this type is the reason the `TimeSource` protocol exists:
/// one call to `Date()`, in Layer 2, where it can be swapped for a fake without
/// any domain code knowing. Trivial as it is, it is the first proof that the
/// adapter seam works end to end, and every later adapter — ink capture,
/// persistence, networking, Keychain — has this exact shape.
public struct SystemTimeSource: TimeSource {
    public init() {}

    public var now: Date { Date() }
}
