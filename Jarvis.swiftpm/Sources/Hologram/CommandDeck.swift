import SwiftUI

/// Buttons for **every** function in the specification, shown while the 3D
/// project space is open (requirement 6). Each button runs the same command
/// path as voice and text.
struct CommandDeck: View {
    @Environment(JarvisController.self) private var jarvis
    @State private var page = 0

    private var ko: Bool { jarvis.currentLanguage == .korean }

    private struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let en: String
        let ko: String
        var active: Bool = false
        var tint: Color = Holo.cyan
        let action: () -> Void
    }

    private var pages: [(String, [Item])] {
        let j = jarvis
        let say: (String, String) -> () -> Void = { en, kr in { j.submit(j.currentLanguage == .korean ? kr : en, modality: .button) } }
        let modelling: [Item] = [
            Item(icon: "hand.raised.fingers.spread.fill", en: "HANDS", ko: "손 인식", active: j.handTrackingEnabled, tint: Holo.amber) {
                Task { await j.setHandTracking(!j.handTrackingEnabled) }
            },
            Item(icon: "cube.fill", en: "CUBE", ko: "큐브", action: say("make a cube", "큐브 만들어")),
            Item(icon: "circle.fill", en: "SPHERE", ko: "구", action: say("make a sphere", "구 만들어")),
            Item(icon: "cylinder.fill", en: "CYLINDER", ko: "원기둥", action: say("make a cylinder", "원기둥 만들어")),
            Item(icon: "cone.fill", en: "CONE", ko: "원뿔", action: say("make a cone", "원뿔 만들어")),
            Item(icon: "circle.circle", en: "TORUS", ko: "토러스", action: say("make a torus", "토러스 만들어")),
            Item(icon: "capsule.fill", en: "CAPSULE", ko: "캡슐", action: say("make a capsule", "캡슐 만들어")),
            Item(icon: "pyramid.fill", en: "PYRAMID", ko: "피라미드", action: say("make a pyramid", "피라미드 만들어")),
            Item(icon: "square.fill", en: "PLANE", ko: "평면", action: say("make a plane", "평면 만들어")),
            Item(icon: "textformat", en: "TEXT", ko: "텍스트", action: say("make text \"JARVIS\"", "텍스트 \"JARVIS\" 만들어")),
            Item(icon: "plus.square.on.square", en: "CLONE", ko: "복제", action: say("clone it", "복제해")),
            Item(icon: "trash", en: "DELETE", ko: "삭제", tint: Holo.red, action: say("delete it", "삭제해")),
            Item(icon: "arrow.uturn.backward", en: "UNDO", ko: "되돌리기", action: say("undo", "되돌려")),
            Item(icon: "arrow.uturn.forward", en: "REDO", ko: "다시", action: say("redo", "다시 실행")),
            Item(icon: "arrow.up.left.and.arrow.down.right", en: "BIGGER", ko: "크게", action: say("make it bigger", "크게 만들어")),
            Item(icon: "arrow.down.right.and.arrow.up.left", en: "SMALLER", ko: "작게", action: say("make it smaller", "작게 만들어")),
            Item(icon: "rotate.right", en: "ROTATE", ko: "회전", action: say("rotate it 45 degrees", "45도 회전해")),
            Item(icon: "paintpalette.fill", en: "GOLD", ko: "금색", action: say("make it gold", "금색으로 바꿔")),
            Item(icon: "sparkles", en: "DESIGN", ko: "설계", action: say("build a helmet", "헬멧 만들어")),
            Item(icon: "square.and.arrow.up", en: "EXPORT", ko: "내보내기", action: say("export the model", "모델 내보내기")),
            Item(icon: "photo.on.rectangle.angled", en: "WALLPAPER", ko: "배경화면", action: say("set as wallpaper", "배경화면으로 저장해")),
            Item(icon: "scope", en: "RESET VIEW", ko: "시점 초기화", action: say("reset the view", "시점 초기화")),
            Item(icon: "xmark.circle", en: "CLEAR", ko: "전체 삭제", tint: Holo.red, action: say("delete everything", "전부 지워")),
        ]
        let system: [Item] = [
            Item(icon: "music.note", en: "MUSIC", ko: "음악", active: j.music.isPlaying, action: say("play some music", "음악 틀어줘")),
            Item(icon: "pause.fill", en: "PAUSE", ko: "일시정지", action: say("pause", "일시정지")),
            Item(icon: "forward.fill", en: "NEXT", ko: "다음 곡", action: say("next song", "다음 곡")),
            Item(icon: "globe", en: "BROWSER", ko: "브라우저", active: j.activePanel == .browser, action: { j.showPanel(j.activePanel == .browser ? nil : .browser) }),
            Item(icon: "clock.arrow.circlepath", en: "HISTORY", ko: "기록", active: j.activePanel == .history, action: { j.showPanel(j.activePanel == .history ? nil : .history) }),
            Item(icon: "brain.head.profile", en: "NEURAL", ko: "신경망", active: j.activePanel == .brain, action: { j.showPanel(j.activePanel == .brain ? nil : .brain) }),
            Item(icon: "bolt.horizontal.circle.fill", en: "DEEP THINK", ko: "심층 사고", active: j.deepThinkEnabled, tint: Holo.amber,
                 action: say(j.deepThinkEnabled ? "deep think off" : "deep think on", j.deepThinkEnabled ? "심층 사고 꺼" : "심층 사고 켜")),
            Item(icon: j.micMuted ? "mic.slash.fill" : "mic.fill", en: "MIC", ko: "마이크", active: !j.micMuted) { j.setMicMuted(!j.micMuted) },
            Item(icon: j.voiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", en: "AI VOICE", ko: "AI 음성", active: !j.voiceMuted) { j.setVoiceMuted(!j.voiceMuted) },
            Item(icon: "person.wave.2.fill", en: "VOICE", ko: "목소리", action: say("use the lewis voice", "목소리 루이스로 바꿔")),
            Item(icon: "hare.fill", en: "FASTER", ko: "빠르게", action: say("speak faster", "빨리 말해")),
            Item(icon: "tortoise.fill", en: "SLOWER", ko: "천천히", action: say("speak slower", "천천히 말해")),
            Item(icon: "flashlight.on.fill", en: "TORCH", ko: "손전등", action: say("turn on the flashlight", "손전등 켜")),
            Item(icon: "sun.max.fill", en: "BRIGHT", ko: "밝게", action: say("brighter", "밝기 올려")),
            Item(icon: "battery.75percent", en: "BATTERY", ko: "배터리", action: say("battery level", "배터리 얼마야")),
            Item(icon: "timer", en: "TIMER 5M", ko: "타이머 5분", action: say("set a timer for 5 minutes", "5분 타이머 맞춰줘")),
            Item(icon: "app.badge", en: "OPEN APP", ko: "앱 열기", action: say("open settings app", "카카오톡 열어줘")),
            Item(icon: "arrow.triangle.2.circlepath", en: "RESUME", ko: "작업 재개", action: say("resume the task", "작업 재개해")),
            Item(icon: "character.bubble", en: "LANGUAGE", ko: "언어", action: say("auto language", "언어 자동")),
            Item(icon: "questionmark.circle", en: "HELP", ko: "도움말", action: { j.showPanel(.help) }),
            Item(icon: "gearshape.fill", en: "SETTINGS", ko: "설정", action: { j.showPanel(.settings) }),
            Item(icon: "moon.zzz.fill", en: "SLEEP", ko: "대기", action: { j.sleep() }),
            Item(icon: "xmark", en: "CLOSE 3D", ko: "3D 닫기", tint: Holo.amber, action: { j.setSpaceOpen(false) }),
        ]
        return [(ko ? "모델링" : "MODELLING", modelling), (ko ? "시스템" : "SYSTEM", system)]
    }

    var body: some View {
        let all = pages
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(all.indices, id: \.self) { i in
                    Button { withAnimation { page = i } } label: {
                        HUDLabel(text: all[i].0, color: page == i ? Holo.cyan : Holo.ice.opacity(0.5), size: 10)
                            .padding(.vertical, 4).padding(.horizontal, 8)
                            .background(Capsule().fill(page == i ? Holo.cyan.opacity(0.15) : .clear))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66, maximum: 84), spacing: 8)], spacing: 8) {
                    ForEach(all[min(page, all.count - 1)].1) { item in
                        HoloButton(icon: item.icon, label: ko ? item.ko : item.en, active: item.active, tint: item.tint, compact: true, action: item.action)
                    }
                }
            }
        }
        .padding(10)
        .holoPanel()
    }
}
