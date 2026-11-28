import SwiftUI

/// Container for side panels.
struct PanelContainer<Content: View>: View {
    let title: String
    let icon: String
    let close: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).foregroundStyle(Holo.cyan).holoGlow(radius: 5)
                HUDLabel(text: title, color: Holo.cyan, size: 12)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Holo.ice)
                        .frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            content
        }
        .padding(14)
        .holoPanel()
    }
}

// MARK: - History (every record)

struct HistoryPanel: View {
    @Environment(JarvisController.self) private var jarvis
    @State private var tab = 0
    @State private var search = ""
    @State private var messages: [RecordKeeper.MessageRecord] = []
    @State private var runs: [RecordKeeper.RunRecord] = []
    @State private var artifacts: [RecordKeeper.ArtifactRecord] = []
    @State private var stats = RecordKeeper.Stats()
    @State private var selectedRun: RecordKeeper.RunRecord?
    @State private var exportedURL: URL?

    private var ko: Bool { jarvis.currentLanguage == .korean }

    var body: some View {
        PanelContainer(title: ko ? "전체 기록" : "Complete record", icon: "clock.arrow.circlepath", close: { jarvis.showPanel(nil) }) {
            statsLine
            tabPicker
            if tab == 0 { searchField }
            ScrollView { recordList }
            footer
        }
        .onAppear(perform: reload)
        .onChange(of: tab) { _, _ in reload() }
    }

    private var statsLine: some View {
        let text: String = ko
            ? "명령 \(stats.commands) · 작업 \(stats.runs) · 메시지 \(stats.messages) · 설명 \(stats.explanations) · 파일 \(stats.artifacts)"
            : "Commands \(stats.commands) · Runs \(stats.runs) · Messages \(stats.messages) · Explanations \(stats.explanations) · Files \(stats.artifacts)"
        return Text(text).font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.7))
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            Text(ko ? "대화" : "Conversation").tag(0)
            Text(ko ? "작업" : "Tasks").tag(1)
            Text(ko ? "파일" : "Files").tag(2)
        }
        .pickerStyle(.segmented)
    }

    private var searchField: some View {
        TextField(ko ? "검색" : "Search", text: $search)
            .textFieldStyle(.roundedBorder)
            .onSubmit(reload)
    }

    private var recordList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            switch tab {
            case 0:
                ForEach(messages) { (m: RecordKeeper.MessageRecord) in
                    HistoryMessageRow(message: m)
                }
            case 1:
                ForEach(runs) { (r: RecordKeeper.RunRecord) in
                    HistoryRunRow(run: r, expanded: selectedRun?.id == r.id, language: jarvis.currentLanguage) {
                        selectedRun = (selectedRun?.id == r.id) ? nil : r
                    }
                }
            default:
                ForEach(artifacts) { (a: RecordKeeper.ArtifactRecord) in
                    HistoryArtifactRow(artifact: a)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(ko ? "대화 내보내기" : "Export transcript") { exportedURL = RecordKeeper.shared.exportTranscript(); reload() }
                .font(Holo.mono(11, .bold)).foregroundStyle(Holo.cyan)
            if let url = exportedURL {
                ShareLink(item: url) { Label(ko ? "공유" : "Share", systemImage: "square.and.arrow.up") }
                    .font(Holo.mono(11)).foregroundStyle(Holo.cyan)
            }
            Spacer()
            Text(ko ? "파일 앱 › Jarvis 폴더에도 저장됩니다" : "Also saved in Files › Jarvis").font(Holo.mono(9)).foregroundStyle(Holo.ice.opacity(0.5))
        }
    }

    private func reload() {
        let r = RecordKeeper.shared
        messages = r.recentMessages(limit: 200, search: search)
        runs = r.recentRuns(limit: 100)
        artifacts = r.recentArtifacts(limit: 100)
        stats = r.stats()
    }
}

// Rows of the history panel, kept as separate small views so each body type-checks quickly.

private struct HistoryMessageRow: View {
    let message: RecordKeeper.MessageRecord

    var body: some View {
        let isUser: Bool = message.role == "user"
        let stamp: String = message.timestamp.formatted(date: .abbreviated, time: .standard)
        return VStack(alignment: .leading, spacing: 2) {
            HUDLabel(text: "\(message.role) · \(stamp)", color: isUser ? Holo.amber : Holo.cyan, size: 8)
            Text(message.text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
    }
}

private struct HistoryRunRow: View {
    let run: RecordKeeper.RunRecord
    let expanded: Bool
    let language: DetectedLanguage
    let toggle: () -> Void

    private var statusIcon: String {
        switch run.status {
        case "succeeded": return "checkmark.circle.fill"
        case "running": return "circle.dotted"
        default: return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch run.status {
        case "succeeded": return Holo.green
        case "running": return Holo.amber
        default: return Holo.red
        }
    }

    private var timing: String {
        let format: String = language == .korean ? "예상 %.1f초 · 실제 %.1f초 · %@" : "est. %.1fs · actual %.1fs · %@"
        let start: String = run.start.formatted(date: .omitted, time: .standard)
        return String(format: format, run.estimated ?? 0, run.actual ?? 0, start)
    }

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: statusIcon).foregroundStyle(statusColor)
                    Text(run.title).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Text(run.action).font(Holo.mono(9)).foregroundStyle(Holo.ice.opacity(0.6))
                }
                Text(timing).font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.6))
                if expanded { details }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var details: some View {
        let explanations: [Explanation] = RecordKeeper.shared.explanations(for: run.id)
        ForEach(Array(explanations.enumerated()), id: \.offset) { (_: Int, e: Explanation) in
            ExplanationCard(explanation: e, language: language)
        }
        if let err = run.error {
            Text(err).font(Holo.mono(10)).foregroundStyle(Holo.red)
        }
    }
}

private struct HistoryArtifactRow: View {
    let artifact: RecordKeeper.ArtifactRecord

    var body: some View {
        let fileName: String = artifact.path.components(separatedBy: "/").last ?? artifact.path
        let size: String = ByteCountFormatter.string(fromByteCount: Int64(artifact.size), countStyle: .file)
        return HStack {
            Image(systemName: "doc.fill").foregroundStyle(Holo.cyan)
            VStack(alignment: .leading) {
                Text(fileName).font(.system(size: 13, design: .rounded)).foregroundStyle(.white)
                Text("\(artifact.description) · \(size)").font(Holo.mono(9)).foregroundStyle(Holo.ice.opacity(0.6))
            }
            Spacer()
            ShareLink(item: JarvisPaths.documents.appendingPathComponent(artifact.path)) {
                Image(systemName: "square.and.arrow.up").foregroundStyle(Holo.cyan)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
    }
}

// MARK: - Help

struct HelpPanel: View {
    @Environment(JarvisController.self) private var jarvis
    private var ko: Bool { jarvis.currentLanguage == .korean }

    private var sections: [(String, [String])] {
        ko ? [
            ("깨우기", ["\"Wake up Jarvis\" / \"자비스 일어나\"", "비상 웨이크 버튼(화면 오른쪽 아래)", "\"잘 자\" → 대기"]),
            ("3D 설계", ["\"금색 바퀴 6개와 스포일러가 달린 빨간 스포츠카 만들어\"", "\"파란 지붕에 굴뚝 있는 이층집\" · \"탑 6개인 성\" · \"눈이 빨간 로봇\"",
                        "만든 뒤 고치기: \"바퀴를 금색으로 바꿔\" · \"굴뚝 추가해\" · \"스포일러 빼줘\" · \"다리 두 개 더\"",
                        "\"높이 2미터\" · \"나무 의자\" · \"유리 탁자\" · \"홀로그램 모드\" / \"실사 모드\""]),
            ("3D 공간", ["\"3D 공간 열어줘\"", "\"빨간 큐브 세 개 만들어\" · \"헬멧 만들어\"", "\"세 번 복제해\" · \"두 배로 키워\" · \"왼쪽으로 30cm 옮겨\"",
                        "마우스 왼쪽 드래그로 이동, 가리킨 채 스크롤로 확대/축소", "\"손 인식 켜\" → 엄지·검지로 집어 이동, 양손 간격으로 크기 조절",
                        "\"배경화면으로 저장해\" · \"모델 내보내기\""]),
            ("음악·웹", ["\"아이유 노래 틀어줘\" · \"일시정지\" · \"다음 곡\"", "\"서울 날씨 검색해줘\" · \"브라우저 열어\""]),
            ("기기", ["\"카카오톡 열어줘\" · \"손전등 켜\" · \"밝기 50%\"", "\"5분 타이머\" · \"오전 7시 알람\" · \"엄마한테 전화해\"",
                     "\"와이파이 꺼\" (Jarvis Bridge 단축어 필요)"]),
            ("대화·설정", ["\"심층 사고 켜\" · \"천천히 말해\" · \"목소리 루이스로 바꿔\"", "\"마이크 꺼\" · \"음성 꺼\" · \"기록 보여줘\" · \"신경망 보여줘\"",
                         "말하는 도중에 말씀하시면 즉시 멈추고 새 요청을 듣습니다"]),
        ] : [
            ("Wake", ["\"Wake up Jarvis\"", "Emergency wake button (bottom right)", "\"Go to sleep\" → standby"]),
            ("3D design", ["\"Design a red sports car with six gold wheels and a spoiler\"", "\"A two-storey house with a blue roof and a chimney\" · \"A castle with 6 towers\"",
                           "Refine it: \"Make the wheels gold\" · \"Add a chimney\" · \"Remove the spoiler\" · \"Two more legs\"",
                           "\"2 metres tall\" · \"a wooden chair\" · \"a glass table\" · \"Hologram mode\" / \"Realistic mode\""]),
            ("3D space", ["\"Open the 3D space\"", "\"Make three red cubes\" · \"Build a helmet\"", "\"Clone it twice\" · \"Make it twice as big\" · \"Move it left 30 cm\"",
                          "Left-click drag to move; scroll while pointing to scale", "\"Hand tracking on\" → pinch to grab, spread both hands to scale",
                          "\"Set as wallpaper\" · \"Export the model\""]),
            ("Music & web", ["\"Play Bohemian Rhapsody\" · \"Pause\" · \"Next song\"", "\"Search for the best ramen in Seoul\" · \"Open the browser\""]),
            ("Device", ["\"Open KakaoTalk\" · \"Torch on\" · \"Brightness 50%\"", "\"Timer for 5 minutes\" · \"Alarm at 7am\" · \"Call mum\"",
                        "\"Turn off Wi-Fi\" (needs the Jarvis Bridge shortcut)"]),
            ("Conversation", ["\"Deep think on\" · \"Speak slower\" · \"Use the Lewis voice\"", "\"Mute the mic\" · \"Text only\" · \"Show history\" · \"Show the neural core\"",
                              "Speak while I'm talking to interrupt me with a new request"]),
        ]
    }

    var body: some View {
        PanelContainer(title: ko ? "도움말" : "Help", icon: "questionmark.circle", close: { jarvis.showPanel(nil) }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sections, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            HUDLabel(text: section.0, color: Holo.amber, size: 10)
                            ForEach(section.1, id: \.self) { line in
                                Button { if line.hasPrefix("\"") { jarvis.submit(line.components(separatedBy: "\"").dropFirst().first ?? line, modality: .button) } } label: {
                                    Text("• " + line).font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Browser

struct BrowserPanel: View {
    @Environment(JarvisController.self) private var jarvis
    @State private var address = ""

    var body: some View {
        PanelContainer(title: jarvis.web.title.isEmpty ? "Browser" : jarvis.web.title, icon: "globe", close: { jarvis.showPanel(nil) }) {
            HStack(spacing: 8) {
                Button { jarvis.web.goBack() } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Holo.cyan)
                Button { jarvis.web.goForward() } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).foregroundStyle(Holo.cyan)
                TextField("https:// · search", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(go)
                Button { jarvis.web.reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).foregroundStyle(Holo.cyan)
                Button { jarvis.submit(jarvis.currentLanguage == .korean ? "이 페이지 요약해줘" : "Summarise this page", modality: .button) } label: {
                    Image(systemName: "text.badge.star")
                }
                .buttonStyle(.plain).foregroundStyle(Holo.amber)
            }
            if jarvis.web.isLoading { ProgressView(value: jarvis.web.progress).tint(Holo.cyan) }
            AgentBrowserView(agent: jarvis.web)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Holo.cyan.opacity(0.3)))
        }
        .onAppear { address = jarvis.web.currentURL?.absoluteString ?? "" }
    }

    private func go() {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        Task {
            if text.contains(".") && !text.contains(" "), let url = URL(string: text.hasPrefix("http") ? text : "https://" + text) {
                await jarvis.web.load(url)
            } else {
                _ = await jarvis.web.search(text)
            }
        }
    }
}
