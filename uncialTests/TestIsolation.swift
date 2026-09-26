import AppKit
import ObjectiveC

/// UserDefaults suites for one test, kept out of the user's ~/Library/Preferences: a suite named by an
/// absolute path is stored at that path (CFPreferences' path form, the one `defaults read /path` takes),
/// so each lives in a temporary folder that `removeAll()` deletes. A named suite became
/// ~/Library/Preferences/<name>.plist, and deleting that file does not work: cfprefsd writes it lazily,
/// after the test is over (probed 2026-09-26).
final class PreferenceSuites: @unchecked Sendable {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("uncial-tests-\(UUID().uuidString)", isDirectory: true)
    private let lock = NSLock()
    private var count = 0

    /// An empty suite of its own.
    func make() -> UserDefaults {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = lock.withLock { () -> Int in
            count += 1
            return count
        }
        return UserDefaults(suiteName: directory.appendingPathComponent("defaults-\(index)").path)!
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// The test host is Uncial itself, under the app's bundle id, so every document a test opens through
/// the document controller would go into the user's real File ▸ Open Recent list (SwiftUI's controller
/// records one even without `openDocument`, probed 2026-09-26). In the test process nothing is recorded.
enum RecentDocuments {
    static func suppress() { _ = suppressed }

    private static let suppressed: Void = {
        let ignore: @convention(block) (AnyObject, AnyObject?) -> Void = { _, _ in }
        for selector in [#selector(NSDocumentController.noteNewRecentDocumentURL(_:)),
                         #selector(NSDocumentController.noteNewRecentDocument(_:))] {
            if let method = class_getInstanceMethod(NSDocumentController.self, selector) {
                method_setImplementation(method, imp_implementationWithBlock(ignore))
            }
        }
    }()
}
