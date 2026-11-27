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
            let answer: Bool? = await answer(within: 8) { done in action(url, completion: done) }
            // No answer yet: iOS is most likely asking the user ("Open in …?" / "Call …?").
            // Trying another route would only show the question twice.
            guard let accepted = answer else { return log(url, "SwiftUI openURL", true, pending: true) }
            if accepted { return log(url, "SwiftUI openURL", true) }
        }
        if let scene = activeScene {
            let answer: Bool? = await answer(within: 8) { done in scene.open(url, options: nil, completionHandler: done) }
            guard let accepted = answer else { return log(url, "window scene", true, pending: true) }
            if accepted { return log(url, "window scene", true) }
        }
        let accepted = await UIApplication.shared.open(url)
        if !accepted { lastRefused = url }
        return log(url, "UIApplication", accepted)
    }

    /// Wait for a completion-handler result; nil when none arrives in time (a handler that never
    /// fires must not leave Jarvis stuck "thinking").
    private static func answer(within seconds: Double, _ start: (@escaping (Bool) -> Void) -> Void) async -> Bool? {
        await withCheckedContinuation { (c: CheckedContinuation<Bool?, Never>) in
            let once = ResumeOnce()
            start { ok in if once.claim() { c.resume(returning: ok) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                if once.claim() { c.resume(returning: nil) }
            }
        }
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private static func log(_ url: URL, _ route: String, _ ok: Bool, pending: Bool = false) -> Bool {
        let scheme: String = url.scheme ?? "?"
        let outcome: String = pending ? "awaiting the user" : (ok ? "opened" : "refused")
        Log.tools.info("Open \(scheme, privacy: .public): via \(route, privacy: .public) -> \(outcome, privacy: .public)")
        return ok
    }
}

/// Resumes a continuation exactly once, whichever of the result or the timeout comes first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
