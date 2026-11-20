import SwiftUI
import WebKit
import MediaPlayer
import Observation

/// Plays requested music **from the web** (YouTube search → first result) in a
/// dedicated web player, with library playback as an alternative. Controlled by
/// voice or text: play / pause / resume / next / stop.
@MainActor
@Observable
final class MusicService: NSObject, WKNavigationDelegate {
    var nowPlaying: String?
    var isPlaying = false
    var lastQuery: String?

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var resultIndex = 0
    @ObservationIgnored private var loadContinuation: CheckedContinuation<Void, Never>?

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        // Keep playback going when the page thinks it is hidden (background / other apps).
        let keepAlive = """
        Object.defineProperty(document, 'hidden', {get: function(){ return false; }});
        Object.defineProperty(document, 'visibilityState', {get: function(){ return 'visible'; }});
        document.addEventListener('visibilitychange', function(e){ e.stopImmediatePropagation(); }, true);
        """
        config.userContentController.addUserScript(WKUserScript(source: keepAlive, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
    }

    private func load(_ url: URL) async {
        webView.load(URLRequest(url: url))
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            loadContinuation?.resume()
            loadContinuation = c
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                self?.loadContinuation?.resume()
                self?.loadContinuation = nil
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.loadContinuation?.resume()
            self.loadContinuation = nil
        }
    }

    /// Search the web for the query and start the first playable result.
    func play(query: String?) async -> (Bool, String) {
        let q = (query?.isEmpty == false ? query! : (lastQuery ?? "relaxing jazz"))
        if query == nil, nowPlaying != nil { return await resume() }
        lastQuery = q
        resultIndex = 0
        return await playResult(q, index: 0)
    }

    private func playResult(_ q: String, index: Int) async -> (Bool, String) {
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard let url = URL(string: "https://m.youtube.com/results?search_query=\(encoded)") else { return (false, "Bad query") }
        await load(url)
        // Give the results page a moment to render its list.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let js = """
        (function(){
          var links=[].slice.call(document.querySelectorAll('a[href^="/watch"]'));
          var seen={}, out=[];
          links.forEach(function(a){ var h=a.getAttribute('href').split('&')[0]; if(!seen[h]){ seen[h]=1;
            var t=(a.getAttribute('aria-label')||a.innerText||'').trim(); out.push([h,t]); } });
          return JSON.stringify(out.slice(0,10));
        })()
        """
        guard let json = try? await webView.evaluateJavaScript(js) as? String, let data = json.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String]], !rows.isEmpty else {
            return (false, "No playable results were found for “\(q)”.")
        }
        let pick = rows[min(index, rows.count - 1)]
        guard let watch = URL(string: "https://m.youtube.com" + pick[0]) else { return (false, "Bad result") }
        await load(watch)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        _ = try? await webView.evaluateJavaScript("(function(){var v=document.querySelector('video'); if(v){v.muted=false; v.play(); return true;} return false;})()")
        let title = pick.count > 1 && !pick[1].isEmpty ? pick[1] : q
        nowPlaying = String(title.prefix(80))
        isPlaying = true
        RecordKeeper.shared.setSetting("music.last", q)
        return (true, nowPlaying ?? q)
    }

    func pause() async -> (Bool, String) {
        _ = try? await webView.evaluateJavaScript("(function(){var v=document.querySelector('video'); if(v){v.pause();}})()")
        MPMusicPlayerController.applicationMusicPlayer.pause()
        isPlaying = false
        return (true, "")
    }

    func resume() async -> (Bool, String) {
        _ = try? await webView.evaluateJavaScript("(function(){var v=document.querySelector('video'); if(v){v.play();}})()")
        isPlaying = nowPlaying != nil
        return (nowPlaying != nil, nowPlaying ?? "Nothing to resume.")
    }

    func stop() async -> (Bool, String) {
        _ = await pause()
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        nowPlaying = nil
        return (true, "")
    }

    func next() async -> (Bool, String) {
        guard let q = lastQuery else { return (false, "Nothing is playing.") }
        resultIndex += 1
        return await playResult(q, index: resultIndex)
    }

    /// Play matching songs from the user's own music library.
    func playFromLibrary(_ query: String) async -> (Bool, String) {
        let status = await withCheckedContinuation { (c: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
            MPMediaLibrary.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else { return (false, "Media library permission denied.") }
        let q = MPMediaQuery.songs()
        q.addFilterPredicate(MPMediaPropertyPredicate(value: query, forProperty: MPMediaItemPropertyTitle, comparisonType: .contains))
        guard let items = q.items, !items.isEmpty else { return (false, "No songs matching “\(query)” in your library.") }
        let player = MPMusicPlayerController.applicationMusicPlayer
        player.setQueue(with: MPMediaItemCollection(items: items))
        player.play()
        nowPlaying = items.first?.title ?? query
        isPlaying = true
        return (true, nowPlaying ?? query)
    }
}

/// Small holographic mini-player that also keeps the web player in the view hierarchy.
struct MusicPlayerHost: UIViewRepresentable {
    let music: MusicService
    func makeUIView(context: Context) -> WKWebView { music.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
