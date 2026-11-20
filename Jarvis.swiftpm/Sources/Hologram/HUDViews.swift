import SwiftUI

/// Top status bar of the HUD.
struct StatusBar: View {
    @Environment(JarvisController.self) private var jarvis

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(Holo.phaseColor(jarvis.phase)).frame(width: 8, height: 8).holoGlow(Holo.phaseColor(jarvis.phase), radius: 6)
                HUDLabel(text: "J.A.R.V.I.S", color: Holo.cyan, size: 12)
            }
            HUDLabel(text: phaseText, color: Holo.phaseColor(jarvis.phase))
            Spacer()
            if jarvis.deepThinkEnabled { HUDLabel(text: "DEEP THINK", color: Holo.amber) }
            if let song = jarvis.music.nowPlaying {
                Label(song, systemImage: jarvis.music.isPlaying ? "music.note" : "pause")
                    .font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.8)).lineLimit(1).frame(maxWidth: 180)
            }
            HUDLabel(text: languageText, color: Holo.ice)
            HUDLabel(text: "CTRL \(Int(jarvis.brain.controlScore * 100))%", color: Holo.green)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute().second())
                    .font(Holo.mono(11, .semibold)).foregroundStyle(Holo.ice.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .holoPanel(corner: 10)
    }

    private var phaseText: String {
        let ko = jarvis.currentLanguage == .korean
        switch jarvis.phase {
        case .asleep: return ko ? "대기 · \"Wake up Jarvis\"" : "STANDBY · SAY \"WAKE UP JARVIS\""
        case .listening: return ko ? "듣는 중" : "LISTENING"
        case .thinking: return ko ? "생각 중" : "THINKING"
        case .speaking: return ko ? "말하는 중" : "SPEAKING"
        }
    }

    private var languageText: String {
        switch jarvis.languageMode {
        case .auto: return "AUTO · \(jarvis.currentLanguage.rawValue.uppercased())"
        case .korean: return "KO"
        case .english: return "EN"
        }
    }
}

/// Hand-tracking overlay: fingertip dots and the manipulation reticle.
struct HandOverlay: View {
    @Environment(JarvisController.self) private var jarvis

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(jarvis.hands.overlayPoints.enumerated()), id: \.offset) { i, p in
                    Circle()
                        .fill(i % 4 < 2 ? Holo.cyan : Holo.ice.opacity(0.4))
                        .frame(width: i % 4 < 2 ? 12 : 7, height: i % 4 < 2 ? 12 : 7)
                        .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                        .holoGlow(Holo.cyan, radius: 6)
                }
                if let r = jarvis.scene.reticle {
                    ZStack {
                        Circle().strokeBorder(jarvis.scene.reticlePinching ? Holo.amber : Holo.cyan, lineWidth: 2).frame(width: 44, height: 44)
                        Circle().fill((jarvis.scene.reticlePinching ? Holo.amber : Holo.cyan).opacity(0.35)).frame(width: 10, height: 10)
                        CornerBrackets(length: 8).stroke(Holo.cyan, lineWidth: 1.5).frame(width: 60, height: 60)
                    }
                    .position(r)
                    .holoGlow(jarvis.scene.reticlePinching ? Holo.amber : Holo.cyan, radius: 8)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Small music mini-player card (also keeps the web player alive in the view hierarchy).
struct MiniPlayer: View {
    @Environment(JarvisController.self) private var jarvis
    var body: some View {
        HStack(spacing: 10) {
            // The web player stays in the window (WebKit needs that for playback) but is
            // shrunk to a single invisible point while nothing is playing.
            MusicPlayerHost(music: jarvis.music)
                .frame(width: jarvis.music.nowPlaying == nil ? 1 : 96, height: jarvis.music.nowPlaying == nil ? 1 : 54)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(jarvis.music.nowPlaying == nil ? 0.01 : 1)
                .allowsHitTesting(jarvis.music.nowPlaying != nil)
            if let song = jarvis.music.nowPlaying {
                VStack(alignment: .leading, spacing: 2) {
                    HUDLabel(text: jarvis.currentLanguage == .korean ? "재생 중" : "Now playing", color: Holo.cyan, size: 8)
                    Text(song).font(.system(size: 12, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                }
                Button { Task { _ = jarvis.music.isPlaying ? await jarvis.music.pause() : await jarvis.music.resume() } } label: {
                    Image(systemName: jarvis.music.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(Holo.cyan)
                }
                .buttonStyle(.plain)
                Button { Task { _ = await jarvis.music.next() } } label: { Image(systemName: "forward.fill").foregroundStyle(Holo.cyan) }
                    .buttonStyle(.plain)
            }
        }
        .padding(jarvis.music.nowPlaying == nil ? 0 : 8)
        .background(jarvis.music.nowPlaying == nil ? AnyView(Color.clear) : AnyView(Color.clear.holoPanel(corner: 10)))
    }
}
