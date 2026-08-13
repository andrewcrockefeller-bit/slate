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
/// It also means a preview or a test can hand any screen a fixed clock, a
/// tweaked configuration, and an in-memory store without touching global state
/// or leaving files behind.
struct AppEnvironment {
    let config: TutorConfig
    let timeSource: any TimeSource
    let documents: any DocumentRepository

    init(
        config: TutorConfig,
        timeSource: any TimeSource,
        documents: any DocumentRepository
    ) {
        self.config = config
        self.timeSource = timeSource
        self.documents = documents
    }

    /// The wiring the shipping app runs with.
    static func live() -> AppEnvironment {
        let timeSource = SystemTimeSource()

        return AppEnvironment(
            config: .default,
            timeSource: timeSource,
            documents: FileDocumentRepository(root: documentsRoot(), timeSource: timeSource)
        )
    }

    /// Deterministic wiring for previews and manual testing.
    ///
    /// In-memory storage on purpose: a preview that writes real documents would
    /// litter the store with junk every time Xcode rebuilt it.
    static func preview(config: TutorConfig = .default) -> AppEnvironment {
        let timeSource = FixedTimeSource.reference

        return AppEnvironment(
            config: config,
            timeSource: timeSource,
            documents: InMemoryDocumentRepository(timeSource: timeSource)
        )
    }

    /// Where documents live.
    ///
    /// Application Support rather than Documents: this is app-managed storage
    /// in a format only Slate reads, not files the user is meant to browse or
    /// hand to another app. Putting it in Documents would expose the internal
    /// layout through the Files app and make the on-disk shape something we
    /// could no longer change freely.
    private static func documentsRoot() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return base
            .appendingPathComponent("Slate", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
    }
}
