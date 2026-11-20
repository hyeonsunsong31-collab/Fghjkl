import AppIntents
import UniformTypeIdentifiers
import UIKit

// App Intents make Jarvis' functions available to Siri, Spotlight, the
// Shortcuts app, Control Center, the Action button and AssistiveTouch when the
// app is installed as a standalone app (TestFlight / Xcode). In Swift
// Playgrounds the equivalent is the "Wake up Jarvis" shortcut using jarvis://wake.

struct WakeJarvisIntent: AppIntent {
    static let title: LocalizedStringResource = "Wake up Jarvis"
    static let description = IntentDescription("Wakes Jarvis, shows the hologram and starts listening.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        JarvisController.shared.wake(source: .shortcut)
        return .result()
    }
}

struct AskJarvisIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Jarvis"
    static let description = IntentDescription("Sends a request to Jarvis by voice or text.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Request")
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult {
        JarvisController.shared.submit(request, modality: .shortcut)
        return .result()
    }
}

struct Open3DSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the 3D project space"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let j = JarvisController.shared
        j.wake(source: .shortcut, speak: false)
        j.setSpaceOpen(true)
        return .result()
    }
}

struct ToggleHandTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Hand tracking"
    static let openAppWhenRun: Bool = true

    @Parameter(title: "On", default: true)
    var enabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        let j = JarvisController.shared
        j.setSpaceOpen(true)
        await j.setHandTracking(enabled)
        return .result()
    }
}

struct MuteMicrophoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute Jarvis' microphone"

    @Parameter(title: "Muted", default: true)
    var muted: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        JarvisController.shared.setMicMuted(muted)
        return .result()
    }
}

struct PlayMusicIntent: AppIntent {
    static let title: LocalizedStringResource = "Play music with Jarvis"
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Song or artist")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        JarvisController.shared.submit("play \(query)", modality: .shortcut)
        return .result()
    }
}

/// Returns the latest wallpaper snapshot — use with Shortcuts' "Set Wallpaper".
struct WorkspaceSnapshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Jarvis 3D workspace image"
    static let description = IntentDescription("Returns the latest snapshot of the 3D workspace for use as a wallpaper.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let latest = RecordKeeper.shared.recentArtifacts(limit: 200).first { $0.path.contains("wallpaper-") }
        guard let latest else {
            throw NSError(domain: "Jarvis", code: 1, userInfo: [NSLocalizedDescriptionKey: "No wallpaper snapshot yet. Say “set as wallpaper” first."])
        }
        let url = JarvisPaths.documents.appendingPathComponent(latest.path)
        return .result(value: IntentFile(fileURL: url, filename: url.lastPathComponent, type: .png))
    }
}

struct JarvisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WakeJarvisIntent(),
                    phrases: ["Wake up \(.applicationName)", "\(.applicationName) wake up", "\(.applicationName) 깨워", "\(.applicationName) 일어나"],
                    shortTitle: "Wake Jarvis", systemImageName: "sparkles")
        AppShortcut(intent: Open3DSpaceIntent(),
                    phrases: ["Open \(.applicationName) workshop", "\(.applicationName) 3D 공간 열어"],
                    shortTitle: "3D Space", systemImageName: "cube.transparent")
        AppShortcut(intent: AskJarvisIntent(),
                    phrases: ["Ask \(.applicationName)", "\(.applicationName)에게 물어봐"],
                    shortTitle: "Ask Jarvis", systemImageName: "text.bubble")
        AppShortcut(intent: WorkspaceSnapshotIntent(),
                    phrases: ["Get \(.applicationName) wallpaper", "\(.applicationName) 배경화면"],
                    shortTitle: "Workspace image", systemImageName: "photo")
    }
}
