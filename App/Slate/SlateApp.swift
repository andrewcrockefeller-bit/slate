import SwiftUI

@main
struct SlateApp: App {

    // Built once, here, and handed down. Nothing in the app reaches for its
    // dependencies; everything is given them.
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            CanvasScreen(environment: environment)
        }
    }
}
