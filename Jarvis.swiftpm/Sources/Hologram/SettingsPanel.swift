import SwiftUI

/// Settings: language, voices, models, background behaviour and setup guides.
struct SettingsPanel: View {
    @Environment(JarvisController.self) private var jarvis
    @State private var idleMinutes: Double = 5
    @State private var showGuide = false
    private var ko: Bool { jarvis.currentLanguage == .korean }

    // Each section is its own small view property so the body type-checks quickly
    // with the Swift compiler bundled in Swift Playground.
    var body: some View {
        PanelContainer(title: ko ? "설정" : "Settings", icon: "gearshape.fill", close: { jarvis.showPanel(nil) }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    languageSection
                    voiceSection
                    modelSection
                    presenceSection
                    permissionSection
                }
                .foregroundStyle(.white)
            }
        }
        .onAppear { idleMinutes = Double(jarvis.records.setting("idleMinutes") ?? "5") ?? 5 }
        .sheet(isPresented: $showGuide) { SetupGuideView().environment(jarvis) }
    }

    private var languageBinding: Binding<LanguageMode> {
        Binding(get: { jarvis.languageMode }, set: { jarvis.setLanguageMode($0) })
    }

    private var languageSection: some View {
        group(ko ? "언어" : "Language") {
            Picker("", selection: languageBinding) {
                Text(ko ? "자동 (입력 언어 따라)" : "Automatic").tag(LanguageMode.auto)
                Text("한국어").tag(LanguageMode.korean)
                Text("English").tag(LanguageMode.english)
            }
            .pickerStyle(.segmented)
        }
    }

    private var voiceSummary: String {
        let korean: String = SpeechOutputService.voiceSummary(for: .korean)
        let english: String = SpeechOutputService.voiceSummary(for: .english)
        return ko ? "한국어 음성: \(korean) · 영어 시스템 대체 음성: \(english)" : "Korean voice: \(korean) · English fallback: \(english)"
    }

    private var voiceSection: some View {
        group(ko ? "영국 신사 음성 (Kokoro 뉴럴)" : "British gentleman voice (Kokoro neural)") {
            Text(jarvis.kokoroStatus).font(Holo.mono(11)).foregroundStyle(Holo.ice.opacity(0.8))
            if let p = jarvis.kokoroProgress { ProgressView(value: p).tint(Holo.cyan) }
            HStack {
                ForEach(KokoroEngine.britishVoices, id: \.self) { (voice: String) in
                    voiceButton(voice)
                }
            }
            if !KokoroEngine.isInstalled && jarvis.kokoroProgress == nil {
                Button(ko ? "Kokoro 음성 내려받기 (약 95MB, 1회)" : "Download Kokoro voice (~95 MB, once)") { jarvis.installKokoro() }
                    .buttonStyle(.borderedProminent).tint(Holo.cyan)
            }
            Text(voiceSummary).font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.6))
            Text(ko ? "더 자연스러운 한국어 남성 음성은 설정 › 손쉬운 사용 › 음성 콘텐츠 › 음성에서 '고품질' 음성을 내려받으면 자동 적용됩니다."
                    : "Higher-quality system voices can be downloaded in Settings › Accessibility › Spoken Content › Voices.")
                .font(.system(size: 11, design: .rounded)).foregroundStyle(Holo.ice.opacity(0.6))
        }
    }

    private func voiceButton(_ voice: String) -> some View {
        let selected: Bool = jarvis.englishVoice == voice
        let title: String = voice.replacingOccurrences(of: "bm_", with: "").capitalized
        return Button(title) {
            jarvis.setEnglishVoice(voice)
            jarvis.speech.speak("Good evening, sir. This is my voice.", language: .english)
        }
        .font(Holo.mono(11, .bold))
        .foregroundStyle(selected ? Holo.deep : Holo.cyan)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(selected ? Holo.cyan : Holo.cyan.opacity(0.12)))
    }

    private var appleIntelligenceLabel: some View {
        let available: Bool = jarvis.appleFM.isAvailable
        let text: String = available
            ? (ko ? "Apple Intelligence: 사용 가능" : "Apple Intelligence: available")
            : "Apple Intelligence: " + (jarvis.appleFM.unavailableReason ?? "—")
        return Label(text, systemImage: available ? "checkmark.seal.fill" : "exclamationmark.triangle")
            .font(Holo.mono(11))
            .foregroundStyle(available ? Holo.green : Holo.amber)
    }

    private var deepThinkBinding: Binding<Bool> {
        Binding(get: { jarvis.deepThinkEnabled }, set: { jarvis.deepThinkEnabled = $0 && jarvis.deepThink.isAvailable })
    }

    private var modelSection: some View {
        let size: String = jarvis.deepThink.recommendedVariant.sizeText
        let downloadTitle: String = ko ? "심층 사고 모델 내려받기 (\(size), 1회)" : "Download Deep-Think model (\(size), once)"
        let status: String = (ko ? "심층 사고 모델: " : "Deep-Think model: ") + jarvis.deepThink.statusText
        return group(ko ? "언어 모델" : "Language models") {
            appleIntelligenceLabel
            Text(status).font(Holo.mono(11)).foregroundStyle(Holo.ice.opacity(0.8))
            if let p = jarvis.deepThink.progress { ProgressView(value: p).tint(Holo.amber) }
            if !jarvis.deepThink.isInstalled && jarvis.deepThink.progress == nil {
                Button(downloadTitle) { jarvis.deepThink.install() }
                    .buttonStyle(.borderedProminent).tint(Holo.amber)
            }
            Toggle(ko ? "심층 사고 모드" : "Deep-think mode", isOn: deepThinkBinding)
                .tint(Holo.amber)
        }
    }

    private var pipBinding: Binding<Bool> {
        Binding(get: { PresenceManager.shared.pipEnabled }, set: { PresenceManager.shared.pipEnabled = $0 })
    }

    private var presenceSection: some View {
        let minutes: String = "\(Int(idleMinutes))" + (ko ? "분" : " min")
        return group(ko ? "상주·백그라운드" : "Presence") {
            HStack {
                Text(ko ? "대화 후 대기 전환까지" : "Return to standby after").font(.system(size: 13))
                Slider(value: $idleMinutes, in: 1...60, step: 1) { _ in jarvis.records.setSetting("idleMinutes", String(Int(idleMinutes))) }
                Text(minutes).font(Holo.mono(11))
            }
            Toggle(ko ? "앱 밖에서 떠 있는 홀로그램(PiP)" : "Floating hologram outside the app (PiP)", isOn: pipBinding)
                .tint(Holo.cyan)
            Button(ko ? "앱 밖 웨이크·자동 실행 설정 가이드" : "Wake & auto-start setup guide") { showGuide = true }
                .foregroundStyle(Holo.cyan)
        }
    }

    private var permissionSection: some View {
        group(ko ? "권한" : "Permissions") {
            Button(ko ? "iOS 설정에서 Jarvis 권한 열기" : "Open Jarvis permissions in iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .foregroundStyle(Holo.cyan)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HUDLabel(text: title, color: Holo.amber, size: 10)
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
    }
}

/// Step-by-step guide for the iOS-level integrations that apps cannot set up themselves.
struct SetupGuideView: View {
    @Environment(JarvisController.self) private var jarvis
    @Environment(\.dismiss) private var dismiss
    private var ko: Bool { jarvis.currentLanguage == .korean }

    var body: some View {
        NavigationStack {
            List {
                Section(ko ? "1. \"Wake up Jarvis\" 단축어 만들기 (Siri·어디서나 깨우기)" : "1. Create the \"Wake up Jarvis\" shortcut (Siri, anywhere)") {
                    Text(ko ? "단축어 앱 › + › '동작 추가' › 'URL 열기' 선택 › URL에 jarvis://wake 입력 › 이름을 'Wake up Jarvis'로 저장합니다. 이제 \"Siri야, Wake up Jarvis\"라고 말하면 어느 화면에서든 자비스가 깨어납니다."
                            : "Shortcuts › + › Add Action › 'Open URL' › enter jarvis://wake › name it 'Wake up Jarvis'. Now \"Siri, Wake up Jarvis\" wakes me from anywhere.")
                    Button(ko ? "단축어 앱 열기" : "Open Shortcuts") { Task { await ShortcutsBridge.openCreateShortcut() } }
                }
                Section(ko ? "2. 항상 떠 있는 비상 웨이크 버튼 (AssistiveTouch)" : "2. Always-on-screen wake button (AssistiveTouch)") {
                    Text(ko ? "설정 › 손쉬운 사용 › 터치 › AssistiveTouch 켜기 › '단일 탭'을 'Wake up Jarvis' 단축어로 지정합니다. 모든 앱 위에 떠 있는 버튼 한 번으로 자비스를 깨웁니다."
                            : "Settings › Accessibility › Touch › AssistiveTouch on › set Single-Tap to the 'Wake up Jarvis' shortcut. A floating button over every app wakes me with one tap.")
                    Text(ko ? "같은 단축어를 제어 센터, 뒷면 탭(손쉬운 사용 › 터치 › 뒷면 탭), 아이폰 동작 버튼에도 지정할 수 있습니다."
                            : "Assign the same shortcut to Control Center, Back Tap (Accessibility › Touch › Back Tap) or the iPhone Action button.")
                }
                Section(ko ? "3. 자동 실행에 가장 가까운 설정" : "3. Closest thing to auto-start") {
                    Text(ko ? "iOS는 전원을 켤 때 앱을 자동 실행하는 기능을 허용하지 않습니다. 대신 단축어 › 자동화 › '충전기 연결 시' 또는 '특정 시간' › 'Wake up Jarvis' 실행 › '즉시 실행'으로 설정하면 자동으로 깨어납니다."
                            : "iOS never lets apps launch at power-on. Instead: Shortcuts › Automation › 'When charger connects' or 'Time of Day' › run 'Wake up Jarvis' › Run Immediately.")
                }
                Section(ko ? "4. 3D 공간을 배경화면으로" : "4. 3D workspace as wallpaper") {
                    Text(ko ? "\"배경화면으로 저장해\"라고 말하면 사진 앨범 'Jarvis Space'에 저장됩니다. 단축어 › 자동화 › '앱을 닫을 때(Jarvis)' › '사진 찾기: 앨범 Jarvis Space, 최신 1개' › '배경화면 설정'을 추가하면 자동으로 바탕화면이 바뀝니다."
                            : "Say \"set as wallpaper\" to save into the 'Jarvis Space' album. Add an automation: 'When Jarvis is closed' › 'Find Photos (album Jarvis Space, latest 1)' › 'Set Wallpaper'.")
                }
                Section(ko ? "5. Jarvis Bridge (시스템 설정·다른 앱 제어)" : "5. Jarvis Bridge (system settings & other apps)") {
                    Text(ko ? "docs/SHORTCUTS.ko.md의 레시피대로 'Jarvis Bridge' 단축어를 만들면 와이파이·블루투스·집중 모드·다크 모드·메시지 전송·홈 장비·다른 앱의 동작까지 음성으로 제어할 수 있습니다."
                            : "Build the 'Jarvis Bridge' shortcut from docs/SHORTCUTS.ko.md to control Wi-Fi, Bluetooth, Focus, Dark Mode, messages, Home accessories and other apps' actions by voice.")
                }
            }
            .navigationTitle(ko ? "설정 가이드" : "Setup guide")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(ko ? "닫기" : "Done") { dismiss() } } }
        }
    }
}

/// First-launch onboarding: permissions, models and guides.
struct OnboardingPanel: View {
    @Environment(JarvisController.self) private var jarvis
    @State private var step = 0
    private var ko: Bool { jarvis.currentLanguage == .korean || Locale.preferredLanguages.first?.hasPrefix("ko") == true }

    var body: some View {
        VStack(spacing: 18) {
            ArcCore(phase: .listening, level: 0.3, size: 140)
            Text("J.A.R.V.I.S").font(Holo.display(30, .bold)).foregroundStyle(Holo.cyan).holoGlow()
            Text(ko ? "완전 로컬 에이전틱 AI · 영국 신사 집사" : "Fully on-device agentic AI · your British butler")
                .font(Holo.mono(12)).foregroundStyle(Holo.ice.opacity(0.8))
            Group {
                switch step {
                case 0:
                    onboardingText(ko ? "마이크·음성 인식·카메라·알림 권한을 허용하면 \"Wake up Jarvis\" 음성 웨이크, 음성 대화, 손동작 3D 조작, 타이머를 사용할 수 있습니다."
                                      : "Allow microphone, speech recognition, camera and notifications for voice wake, conversation, gesture control and timers.")
                    Button(ko ? "권한 허용" : "Grant permissions") {
                        Task {
                            _ = await jarvis.speechInput.requestAuthorization()
                            _ = await DeviceControls.requestNotificationPermission()
                            step = 1
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(Holo.cyan)
                case 1:
                    onboardingText(ko ? "영국 신사 음성(Kokoro)을 한 번만 내려받으면(약 95MB) 이후 완전 오프라인으로 동작합니다. 지금 내려받지 않으면 시스템 음성을 사용합니다."
                                      : "Download the British gentleman voice (Kokoro, ~95 MB) once; afterwards everything runs offline. Otherwise the system voice is used.")
                    HStack {
                        Button(ko ? "내려받기" : "Download") { jarvis.installKokoro(); step = 2 }.buttonStyle(.borderedProminent).tint(Holo.cyan)
                        Button(ko ? "나중에" : "Later") { step = 2 }.foregroundStyle(Holo.ice)
                    }
                default:
                    onboardingText(ko ? "앱 밖에서도 깨우려면 설정 › 가이드의 'Wake up Jarvis' 단축어와 AssistiveTouch 설정을 해 주십시오. 언제든 화면 오른쪽 아래 비상 웨이크 버튼으로 깨울 수 있습니다."
                                      : "To wake me outside the app, follow the 'Wake up Jarvis' shortcut and AssistiveTouch guide in Settings. The emergency wake button is always at the bottom right.")
                    Button(ko ? "시작하기" : "Begin") {
                        jarvis.records.setSetting("onboarded", "1")
                        jarvis.showPanel(nil)
                        jarvis.wake(source: .button)
                    }
                    .buttonStyle(.borderedProminent).tint(Holo.cyan)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 560)
        .holoPanel(corner: 20)
    }

    private func onboardingText(_ s: String) -> some View {
        Text(s).font(.system(size: 15, design: .rounded)).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center)
    }
}
