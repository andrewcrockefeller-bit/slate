import Foundation
import SlateCore
import SlatePlatform

/// Everything the app is wired with, assembled in one place.
///
/// Passed down explicitly rather than reached for through a singleton or a
/// global. It is more typing at every call site and it is worth it: the wiring
/// of this app is the thing most likely to be misremembered in three months,
/// and a value you can print is easier to reason about than an ambient one.
///
/// It also means a preview or a test can hand any screen a fixed clock and a
/// tweaked configuration without touching global state.
struct AppEnvironment {
    let config: TutorConfig
    let timeSource: any TimeSource

    init(config: TutorConfig, timeSource: any TimeSource) {
        self.config = config
        self.timeSource = timeSource
    }

    /// The wiring the shipping app runs with.
    static func live() -> AppEnvironment {
        AppEnvironment(
            config: .default,
            timeSource: SystemTimeSource()
        )
    }

    /// Deterministic wiring for previews and manual testing.
    static func preview(config: TutorConfig = .default) -> AppEnvironment {
        AppEnvironment(
            config: config,
            timeSource: FixedTimeSource.reference
        )
    }
}
