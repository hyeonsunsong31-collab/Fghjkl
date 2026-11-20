import SwiftUI
import WebKit
import Observation

/// Jarvis' own web browser with full agentic control: navigate, search, read
/// page text, click, fill forms, scroll and save downloads as artefacts.
/// (Safari itself cannot be scripted by other apps; this browser can.)
@MainActor
@Observable
final class WebAgent: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    var currentURL: URL?
    var title = ""
    var isLoading = false
    var progress: Double = 0

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var loadContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        observations.append(webView.observe(\.estimatedProgress) { [weak self] wv, _ in
            Task { @MainActor in self?.progress = wv.estimatedProgress }
        })
    }

    // MARK: Navigation

    func load(_ url: URL) async {
        isLoading = true
        webView.load(URLRequest(url: url))
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            loadContinuation?.resume()
            loadContinuation = c
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.finishLoad()
            }
        }
    }

    private func finishLoad() {
        isLoading = false
        currentURL = webView.url
        title = webView.title ?? ""
        loadContinuation?.resume()
        loadContinuation = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finishLoad() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishLoad() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishLoad() }
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }

    // MARK: Agent actions

    func evaluate(_ script: String) async -> Any? {
        try? await webView.evaluateJavaScript(script)
    }

    struct SearchResult: Equatable {
        var title: String
        var url: String
        var snippet: String
    }

    /// Search the web (DuckDuckGo HTML endpoint: no account or API key) and parse the results.
    func search(_ query: String) async -> [SearchResult] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://html.duckduckgo.com/html/?q=\(q)") else { return [] }
        await load(url)
        let js = """
        (function(){
          var out=[]; var items=document.querySelectorAll('.result');
          for (var i=0;i<items.length && out.length<6;i++){
            var a=items[i].querySelector('.result__a'); var s=items[i].querySelector('.result__snippet');
            if(!a) continue;
            var href=a.getAttribute('href')||'';
            var m=href.match(/uddg=([^&]+)/); if(m){ href=decodeURIComponent(m[1]); }
            out.push([a.innerText, href, s? s.innerText : '']);
          }
          return JSON.stringify(out);
        })()
        """
        guard let json = await evaluate(js) as? String, let data = json.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return [] }
        return rows.compactMap { r in r.count == 3 ? SearchResult(title: r[0], url: r[1], snippet: r[2]) : nil }
    }

    /// Readable text of the current (or given) page, trimmed for the language model.
    func readPage(_ urlString: String? = nil, limit: Int = 3000) async -> String {
        if let s = urlString, s != "current", let url = URL(string: s.hasPrefix("http") ? s : "https://" + s) {
            await load(url)
        }
        let js = """
        (function(){
          var main=document.querySelector('article')||document.querySelector('main')||document.body;
          var t=(main?main.innerText:'')||''; return t.replace(/\\n{3,}/g,'\\n\\n');
        })()
        """
        let text = (await evaluate(js) as? String) ?? ""
        let header = title.isEmpty ? "" : "\(title)\n"
        return String((header + text).prefix(limit))
    }

    /// Click the first link/button whose visible text contains `text`.
    func click(text: String) async -> Bool {
        let safe = text.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function(){
          var els=document.querySelectorAll('a,button,input[type=submit],[role=button]');
          for (var i=0;i<els.length;i++){ var t=(els[i].innerText||els[i].value||'').toLowerCase();
            if(t.indexOf('\(safe.lowercased())')>=0){ els[i].click(); return true; } }
          return false;
        })()
        """
        return (await evaluate(js) as? Bool) ?? false
    }

    /// Fill the first input matching a CSS selector (or the first text field).
    func fill(selector: String?, value: String) async -> Bool {
        let sel = (selector ?? "input[type=text],input[type=search],textarea").replacingOccurrences(of: "'", with: "\\'")
        let val = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function(){ var el=document.querySelector('\(sel)'); if(!el) return false;
          el.focus(); el.value='\(val)'; el.dispatchEvent(new Event('input',{bubbles:true})); return true; })()
        """
        return (await evaluate(js) as? Bool) ?? false
    }

    func scroll(down: Bool) async {
        _ = await evaluate("window.scrollBy(0, \(down ? 600 : -600));")
    }

    func openFirstResult() async -> Bool {
        let js = "(function(){var a=document.querySelector('.result__a'); if(a){a.click(); return true;} return false;})()"
        return (await evaluate(js) as? Bool) ?? false
    }

    // MARK: Downloads → artefacts

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    nonisolated func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        Task { @MainActor in download.delegate = self }
    }

    nonisolated func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let dir = JarvisPaths.ensure(JarvisPaths.artifacts.appendingPathComponent("Downloads"))
        let url = dir.appendingPathComponent(suggestedFilename)
        try? FileManager.default.removeItem(at: url)
        await MainActor.run { self.downloadDestinations[ObjectIdentifier(download)] = url }
        return url
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        Task { @MainActor in
            if let url = self.downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) {
                RecordKeeper.shared.registerArtifact(at: url, runID: nil, description: "Web download")
            }
        }
    }
}

/// SwiftUI wrapper for the agent browser.
struct AgentBrowserView: UIViewRepresentable {
    let agent: WebAgent
    func makeUIView(context: Context) -> WKWebView { agent.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
