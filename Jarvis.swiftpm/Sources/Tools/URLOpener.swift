import SwiftUI
import UIKit
import os

/// Opens URLs that leave Jarvis: other apps, phone calls, messages, Shortcuts, the App Store.
///
/// Inside Swift Playground, Jarvis runs *hosted* by the Playground app, and iOS can refuse a
/// plain `UIApplication.open` because Jarvis is not the frontmost application. So every route
/// iOS offers is tried in turn until one succeeds:
/// 1. SwiftUI's `openURL` action (what `Link` uses), captured from the root view;
/// 2. the window scene's `open`, which asks on behalf of the scene;
/// 3. `UIApplication.shared.open`.
@MainActor
enum URLOpener {
    /// SwiftUI's environment action, set by the root view on appear.
    static var swiftUIOpen: OpenURLAction?
    /// The last URL that every route refused; offered to the user as a tap-to-open button.
    static var lastRefused: URL?

    @discardableResult
    static func open(_ url: URL) async -> Bool {
        CrashLog.breadcrumb("open url: \(url.scheme ?? "")")
        lastRefused = nil
        if let action = swiftUIOpen {
            let accepted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                action(url) { ok in c.resume(returning: ok) }
            }
            if accepted { return log(url, "SwiftUI openURL", true) }
        }
        if let scene = activeScene {
            let accepted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                scene.open(url, options: nil) { ok in c.resume(returning: ok) }
            }
            if accepted { return log(url, "window scene", true) }
        }
        let accepted = await UIApplication.shared.open(url)
        if !accepted { lastRefused = url }
        return log(url, "UIApplication", accepted)
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private static func log(_ url: URL, _ route: String, _ ok: Bool) -> Bool {
        let scheme: String = url.scheme ?? "?"
        let outcome: String = ok ? "opened" : "refused"
        Log.tools.info("Open \(scheme, privacy: .public): via \(route, privacy: .public) -> \(outcome, privacy: .public)")
        return ok
    }
}
