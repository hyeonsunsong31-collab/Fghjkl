import Foundation
import os

/// Unified logging categories (visible in Console.app when connected to a Mac).
enum Log {
    static let subsystem = "com.jarvis.local.assistant"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let agent = Logger(subsystem: subsystem, category: "agent")
    static let voice = Logger(subsystem: subsystem, category: "voice")
    static let brain = Logger(subsystem: subsystem, category: "brain")
    static let space = Logger(subsystem: subsystem, category: "space3d")
    static let tools = Logger(subsystem: subsystem, category: "tools")
    static let memory = Logger(subsystem: subsystem, category: "memory")
    static let model = Logger(subsystem: subsystem, category: "model")
}

/// Well-known directories inside the app sandbox. `Documents/Jarvis` is visible
/// in the Files app (UIFileSharingEnabled), so every log and artefact is accessible.
enum JarvisPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var root: URL { ensure(documents.appendingPathComponent("Jarvis", isDirectory: true)) }
    static var logs: URL { ensure(root.appendingPathComponent("Logs", isDirectory: true)) }
    static var artifacts: URL { ensure(root.appendingPathComponent("Artifacts", isDirectory: true)) }
    static var projects: URL { ensure(root.appendingPathComponent("Projects", isDirectory: true)) }
    static var exports: URL { ensure(root.appendingPathComponent("Exports", isDirectory: true)) }
    static var database: URL { root.appendingPathComponent("jarvis.sqlite") }

    /// Large downloaded models live in Application Support (not backed up to iCloud).
    static var models: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = ensure(base.appendingPathComponent("Models", isDirectory: true))
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
        return url
    }
    static var brain: URL { ensure(root.appendingPathComponent("Brain", isDirectory: true)) }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
