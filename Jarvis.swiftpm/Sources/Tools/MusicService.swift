import SwiftUI
import WebKit
import MediaPlayer
import Observation
import os

/// Plays requested music **from the web** (YouTube search → the matching result) in a
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
        // Idle player must not show as a grey box on the HUD.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
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

    @ObservationIgnored private var results: [YouTubeResults.Video] = []

    /// Find the requested song on YouTube and play exactly that video.
    func play(query: String?) async -> (Bool, String) {
        if query == nil, nowPlaying != nil { return await resume() }
        let q = (query?.isEmpty == false ? query! : (lastQuery ?? "relaxing jazz"))
        lastQuery = q
        resultIndex = 0
        // Deterministic: read the search results data itself (in result order), not a half-rendered page.
        results = await Self.searchYouTube(q)
        guard !results.isEmpty else { return await playByScraping(q, index: 0) }
        let pick = YouTubeResults.bestMatch(results, for: q) ?? results[0]
        resultIndex = results.firstIndex(of: pick) ?? 0
        return await playVideo(pick, query: q)
    }

    /// YouTube search results for a query (video results only), best first.
    nonisolated static func searchYouTube(_ query: String) async -> [YouTubeResults.Video] {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: query), URLQueryItem(name: "sp", value: "EgIQAQ==")]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("CONSENT=YES+cb; SOCS=CAI", forHTTPHeaderField: "Cookie")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return YouTubeResults.parse(String(decoding: data, as: UTF8.self))
    }

    private func playVideo(_ video: YouTubeResults.Video, query q: String) async -> (Bool, String) {
        let title = video.title.isEmpty ? q : video.title
        // Show the player first: a visible web view keeps WebKit's autoplay happy.
        nowPlaying = String(title.prefix(80))
        isPlaying = true
        Log.tools.info("Music: \(q, privacy: .public) -> \(title, privacy: .public) [\(video.id, privacy: .public)]")
        guard let watch = URL(string: "https://m.youtube.com/watch?v=\(video.id)") else { return (false, "Bad result") }
        await load(watch)
        await startPlayback()
        RecordKeeper.shared.setSetting("music.last", q)
        return (true, nowPlaying ?? q)
    }

    /// Start the video; for the first minute also press YouTube's own "Skip ad" button
    /// when it appears (what a person would do), so the requested song follows quickly.
    private func startPlayback() async {
        let js = """
        (function(){
          window.__jarvisUserPaused = false;
          function kick(){
            var v=document.querySelector('video');
            if(v && !window.__jarvisUserPaused){ v.muted=false; if(v.paused){ v.play(); } }
            var s=document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-skip-button-container button');
            if(s){ s.click(); }
            if(++window.__jarvisKicks > 40){ clearInterval(window.__jarvisKick); window.__jarvisKick = null; }
          }
          window.__jarvisKicks = 0;
          if(window.__jarvisKick){ clearInterval(window.__jarvisKick); }
          window.__jarvisKick = setInterval(kick, 1500);
          kick();
          return !!document.querySelector('video');
        })()
        """
        for _ in 0..<6 {
            if (try? await webView.evaluateJavaScript(js)) as? Bool == true { break }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }

    /// Fallback when the results data could not be read: wait for the rendered results list.
    private func playByScraping(_ q: String, index: Int) async -> (Bool, String) {
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard let url = URL(string: "https://m.youtube.com/results?search_query=\(encoded)&sp=EgIQAQ%253D%253D") else { return (false, "Bad query") }
        await load(url)
        let js = """
        (function(){
          var links=[].slice.call(document.querySelectorAll('ytm-video-with-context-renderer a[href^="/watch"], ytm-compact-video-renderer a[href^="/watch"], ytm-search a[href^="/watch"]'));
          var seen={}, out=[];
          links.forEach(function(a){ var h=a.getAttribute('href').split('&')[0]; if(!seen[h]){ seen[h]=1;
            var t=(a.getAttribute('aria-label')||a.innerText||'').trim(); out.push([h,t]); } });
          return JSON.stringify(out.slice(0,10));
        })()
        """
        var rows: [[String]] = []
        for _ in 0..<10 {   // results render after the page loads: poll for up to ~7 s
            try? await Task.sleep(nanoseconds: 700_000_000)
            if let json = try? await webView.evaluateJavaScript(js) as? String, let data = json.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String]], !parsed.isEmpty {
                rows = parsed
                break
            }
        }
        guard !rows.isEmpty else { return (false, "No playable results were found for \u{201C}\(q)\u{201D}.") }
        let videos = rows.compactMap { row -> YouTubeResults.Video? in
            guard let href = row.first, let r = href.range(of: "v=") else { return nil }
            return YouTubeResults.Video(id: String(href[r.upperBound...].prefix(11)), title: row.count > 1 ? row[1] : "")
        }
        results = videos
        let pick = index == 0 ? (YouTubeResults.bestMatch(videos, for: q) ?? videos[0]) : videos[min(index, videos.count - 1)]
        return await playVideo(pick, query: q)
    }

    func pause() async -> (Bool, String) {
        _ = try? await webView.evaluateJavaScript("(function(){window.__jarvisUserPaused=true; var v=document.querySelector('video'); if(v){v.pause();}})()")
        MPMusicPlayerController.applicationMusicPlayer.pause()
        isPlaying = false
        return (true, "")
    }

    func resume() async -> (Bool, String) {
        _ = try? await webView.evaluateJavaScript("(function(){window.__jarvisUserPaused=false; var v=document.querySelector('video'); if(v){v.play();}})()")
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
        if resultIndex < results.count { return await playVideo(results[resultIndex], query: q) }
        return await playByScraping(q, index: resultIndex)
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
