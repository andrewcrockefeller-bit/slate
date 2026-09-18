import UIKit

enum Haptics {
    static func toolSelect()  { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func hintArrive()  { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func shapeSnap()   { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func stepCorrect() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    // Deliberately absent: any haptic on a tutor refusal, a wrong step, or
    // an error. Never punish with the taptic engine.
}
