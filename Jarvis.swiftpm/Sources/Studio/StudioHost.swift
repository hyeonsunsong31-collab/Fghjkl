import Foundation
import JavaScriptCore
import WebKit
import os

/// What the Jarvis shell cannot do on its own (iOS runs no foreign executables): JavaScript in
/// JavaScriptCore, web pages in WebKit (preview and automatic checks), links for other devices,
/// downloads the user asked for, and the coding agent.
@MainActor
final class StudioHost: ShellHost {
    weak var controller: StudioController?
    private let server = LocalWebServer()
    private var servedLink: URL?

    func perform(_ kind: String, path: String, args: [String], shell: Shell, stdin: [UInt8]) async -> ShellOutput? {
        switch kind {
        case "js":
            return runJavaScript(path: path, args: args, shell: shell, stdin: stdin)
        case "python":
            return .fail("python: Python runs in the browser through Pyodide; open an .html page that loads Pyodide and use 'preview'", 127)
        case "preview", "open", "edit":
            guard let url = try? shell.fs.url(path) else { return .fail("\(kind): \(path) not found") }
            controller?.previewURL = url
            controller?.previewReload += 1
            return .ok("showing \(path) in the Preview tab")
        case "serve", "share":
            guard let folder = try? shell.fs.url(path) else { return .fail("\(kind): \(path) not found") }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
            let base = exists && isDirectory.boolValue ? folder : folder.deletingLastPathComponent()
            guard let link = await server.serve(base) else { return .fail("\(kind): could not open a port") }
            servedLink = link
            let page: String = exists && !isDirectory.boolValue ? folder.lastPathComponent : ""
            let full = link.appendingPathComponent(page)
            return .ok("\(full.absoluteString)\nOpen it on any device on the same Wi-Fi while Jarvis is running.")
        case "verify":
            guard let url = try? shell.fs.url(path) else { return .fail("verify: \(path) not found") }
            let checks = await verify(entryURL: url)
            let failed = checks.contains { $0.hasPrefix("✗") }
            let text = checks.joined(separator: "\n")
            return failed ? ShellOutput(stdout: Array(text.utf8), stderr: "", status: 1) : .ok(text)
        default:
            return nil
        }
    }

    func agent(_ request: String, shell: Shell) async -> ShellOutput? {
        guard let controller else { return nil }
        let korean = Hangul.hangulRatio(request) > 0.3
        controller.request(request, korean: korean)
        return .ok(korean ? "요청을 작업 대기열에 추가했습니다." : "Request queued for this workspace.")
    }

    func fetch(_ url: URL) async throws -> (data: Data, mime: String?) {
        let (data, response) = try await URLSession.shared.data(from: url)
        return (data, response.mimeType)
    }

    /// Serve a folder to the local network; nil when no port could be opened.
    func link(for folder: URL) async -> URL? {
        let link = await server.serve(folder)
        if let link { servedLink = link }
        return link
    }

    // MARK: JavaScript

    /// Run a script in JavaScriptCore with console output, argv and stdin, like `node file.js`.
    private func runJavaScript(path: String, args: [String], shell: Shell, stdin: [UInt8]) -> ShellOutput {
        guard let code = try? shell.fs.readText(path) else { return .fail("node: cannot read \(path)") }
        guard let context = JSContext() else { return .fail("node: JavaScriptCore unavailable") }
        let output = ScriptOutput()
        let log: @convention(block) () -> Void = {
            let parts = (JSContext.currentArguments() as? [JSValue] ?? []).map { $0.toString() ?? "" }
            output.append(parts.joined(separator: " "))
        }
        let console = JSValue(newObjectIn: context)
        let logFunction: AnyObject = unsafeBitCast(log, to: AnyObject.self)
        for name in ["log", "info", "warn", "error", "debug"] { console?.setObject(logFunction, forKeyedSubscript: name as NSString) }
        context.setObject(console, forKeyedSubscript: "console" as NSString)
        let process = JSValue(newObjectIn: context)
        process?.setObject(["node", path] + args, forKeyedSubscript: "argv" as NSString)
        process?.setObject(String(decoding: stdin, as: UTF8.self), forKeyedSubscript: "stdin" as NSString)
        context.setObject(process, forKeyedSubscript: "process" as NSString)
        context.exceptionHandler = { _, exception in
            output.fail(exception?.toString() ?? "error")
        }
        let started = Date()
        let result = context.evaluateScript(code, withSourceURL: URL(string: "file://" + path))
        if let value = result, !value.isUndefined, !value.isNull, output.isEmpty, let text = value.toString() {
            output.append(text)
        }
        let elapsed = Date().timeIntervalSince(started)
        Log.agent.info("Studio: ran a script in \(String(format: "%.2f", elapsed), privacy: .public)s")
        return ShellOutput(stdout: Array(output.text.utf8), stderr: output.error, status: output.error.isEmpty ? 0 : 1)
    }

    // MARK: Checking web products

    /// Open a page in WebKit (off screen) and report: runtime errors, and the product's own
    /// `selfTest()` results (games and apps made by Jarvis expose one).
    func verify(entryURL: URL) async -> [String] {
        let probe = PageProbe()
        let checks = await probe.check(entryURL)
        Log.agent.info("Studio: verified \(entryURL.lastPathComponent, privacy: .public) — \(checks.filter { $0.hasPrefix("✗") }.count, privacy: .public) problem(s)")
        return checks
    }
}

/// Collects console output and the first error of a script run.
private final class ScriptOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private var failure = ""

    func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
    func fail(_ message: String) { lock.lock(); if failure.isEmpty { failure = message }; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n" }
    var error: String { lock.lock(); defer { lock.unlock() }; return failure }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return lines.isEmpty }
}

/// Loads a page in an off-screen web view, records errors and runs its self-test.
@MainActor
private final class PageProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView?
    private var errors: [String] = []
    private var loaded: CheckedContinuation<Bool, Never>?

    func check(_ url: URL) async -> [String] {
        let configuration = WKWebViewConfiguration()
        let capture = """
        window.addEventListener('error', function (e) { window.webkit.messageHandlers.jarvisProbe.postMessage('error: ' + e.message); });
        window.addEventListener('unhandledrejection', function (e) { window.webkit.messageHandlers.jarvisProbe.postMessage('promise: ' + (e.reason && e.reason.message || e.reason)); });
        """
        configuration.userContentController.addUserScript(WKUserScript(source: capture, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(self, name: "jarvisProbe")
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 900), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        let ok: Bool = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            loaded = c
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self?.finishLoading(false)
            }
        }
        var checks: [String] = []
        if !ok { checks.append("✗ the page did not load") }
        try? await Task.sleep(nanoseconds: 500_000_000)
        let script = """
        (function () {
          try {
            var t = window.__game || window.__app;
            if (!t || !t.selfTest) return JSON.stringify({ none: true });
            var r = t.selfTest();
            return JSON.stringify(r);
          } catch (e) { return JSON.stringify({ ok: false, details: ['✗ selfTest threw: ' + e.message] }); }
        })()
        """
        if ok, let raw = try? await view.evaluateJavaScript(script) as? String, let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["none"] != nil {
                checks.append("• no built-in self-test on this page")
            } else {
                for line in json["details"] as? [String] ?? [] { checks.append(line) }
                if (json["ok"] as? Bool) == true && checks.isEmpty { checks.append("✓ self-test passed") }
            }
        }
        for e in errors.prefix(5) { checks.append("✗ " + e) }
        if ok && errors.isEmpty { checks.append("✓ no runtime errors") }
        view.configuration.userContentController.removeScriptMessageHandler(forName: "jarvisProbe")
        webView = nil
        return checks
    }

    private func finishLoading(_ ok: Bool) {
        guard let c = loaded else { return }
        loaded = nil
        c.resume(returning: ok)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finishLoading(true) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.errors.append("load: " + message)
            self.finishLoading(false)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.errors.append("load: " + message)
            self.finishLoading(false)
        }
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // WebKit delivers script messages on the main thread.
        MainActor.assumeIsolated {
            self.errors.append(String(describing: message.body))
        }
    }
}
