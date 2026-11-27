import UIKit

/// Bridge to the Shortcuts app — the officially supported way for an iOS app
/// to reach system settings (Wi-Fi, Bluetooth, Focus, Low Power, Appearance,
/// volume, wallpaper…), send messages, control HomeKit scenes and run the
/// App Intents of every other installed app.
///
/// Jarvis calls a user-created shortcut named **"Jarvis Bridge"** with a JSON
/// payload (see docs/SHORTCUTS.ko.md for the recipe) or runs any named shortcut.
enum ShortcutsBridge {
    static let bridgeName = "Jarvis Bridge"

    /// Run a named shortcut, optionally passing text input. Returns true if Shortcuts opened.
    @MainActor
    @discardableResult
    static func run(_ name: String, input: String? = nil) async -> Bool {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        var items = [URLQueryItem(name: "name", value: name)]
        if let input {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }
        items.append(URLQueryItem(name: "x-success", value: "jarvis://bridge?status=success"))
        items.append(URLQueryItem(name: "x-error", value: "jarvis://bridge?status=error"))
        items.append(URLQueryItem(name: "x-cancel", value: "jarvis://bridge?status=cancel"))
        components.queryItems = items
        guard let url = components.url else { return false }
        return await URLOpener.open(url)
    }

    /// Send a structured action to the Jarvis Bridge shortcut.
    @MainActor
    @discardableResult
    static func bridge(action: String, _ parameters: [String: String]) async -> Bool {
        var payload = parameters
        payload["action"] = action
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return false }
        return await run(bridgeName, input: json)
    }

    /// Change a system setting via the bridge.
    @MainActor
    static func setSystemSetting(_ setting: String, value: String) async -> Bool {
        await bridge(action: "setting", ["setting": setting, "value": value])
    }

    /// Open the Shortcuts app on the "new shortcut" screen (for onboarding guides).
    @MainActor
    static func openCreateShortcut() async {
        if let url = URL(string: "shortcuts://create-shortcut") { _ = await URLOpener.open(url) }
    }
}
