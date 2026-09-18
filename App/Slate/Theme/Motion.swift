import SwiftUI
import UIKit

enum Motion {
    // Standard UI: critically damped, no overshoot
    static let standard = Animation.spring(response: 0.28, dampingFraction: 1.00)
    // Surfaces arriving under their own power
    static let arrive   = Animation.spring(response: 0.38, dampingFraction: 0.86)
    // Committing a snap / settling after a gesture supplied momentum
    static let settle   = Animation.spring(response: 0.30, dampingFraction: 0.78)
    // Rail open/close  (Phase 2, defined now for completeness)
    static let rail     = Animation.spring(response: 0.34, dampingFraction: 0.90)
    // Sheets and popovers
    static let sheet    = Animation.spring(response: 0.40, dampingFraction: 0.88)

    static let undoStroke: Double = 0.09  // reverse-draw duration
    static let inkSettle:  Double = 0.12  // opacity bloom after stroke completes
    static let tickDraw:   Double = 0.18  // margin tick draw-on (Phase 2)
    static let chromeFade: Double = 0.30  // toolbar return after pencil lift
    static let scaleHUD:   Double = 0.40  // zoom indicator fade-out delay

    /// Respect Reduce Motion at the single point of use.
    static func adaptive(_ animation: Animation) -> Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .easeInOut(duration: 0.15)
            : animation
    }

    /// UIKit twin of `.settle` (response: 0.30, dampingFraction: 0.78) —
    /// same numbers, not a new value. `UIViewPropertyAnimator` can't consume
    /// a SwiftUI `Animation` directly, and INK-7's zoom-settle drives
    /// `UIScrollView.zoomScale`, a UIKit property, so it needs this form
    /// instead. Added for INK-7 — not in the original token spec.
    static func settleSpringTiming(initialVelocity: CGVector = .zero) -> UISpringTimingParameters {
        UISpringTimingParameters(dampingRatio: 0.78, initialVelocity: initialVelocity)
    }
    static let settleResponse: TimeInterval = 0.30
}
