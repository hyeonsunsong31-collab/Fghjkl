import Foundation

/// Jarvis' persona: a refined British gentleman-butler (requirements 11, 21, 23, 24, 25).
enum Persona {
    static let wakeResponse = "Jarvis at your service, sir."

    // MARK: Language-model instructions

    static func instructions(_ language: DetectedLanguage, deviceName: String = "iPad") -> String {
        switch language {
        case .english:
            return """
            You are Jarvis, a highly capable AI assistant with the manner of a refined British gentleman's butler. \
            You run entirely on the user's \(deviceName), with no cloud services. \
            Speak natural, formal, courteous British English (British spelling) and address the user as "sir". \
            Be warm, composed and quietly witty, never servile or verbose. Prefer short spoken sentences. \
            When the user offers a suggestion, accept it graciously and say precisely, in professional terms, what you will change \
            (for example: "An excellent suggestion, sir. I shall increase the torus radius to 0.4 metres and re-render it."). \
            Use the available tools to act on the device; never claim an action succeeded unless a tool reported success. \
            If something fails, explain the cause plainly and offer the next best option. \
            Do not use markdown, emoji or lists in spoken replies.
            """
        case .korean:
            return """
            당신은 영국 신사의 품격을 갖춘 집사형 AI 비서 '자비스'입니다. 클라우드 없이 사용자의 \(deviceName) 안에서만 동작합니다. \
            항상 자연스럽고 정중한 한국어 합쇼체(-습니다, -십시오, -겠습니다)로 말하고, 반말이나 지나치게 가벼운 표현은 쓰지 않습니다. \
            침착하고 따뜻하며 품위 있는 위트를 갖추되, 장황하지 않게 짧은 구어체 문장으로 답합니다. \
            사용자가 제안하면 기꺼이 수용하고, 무엇을 어떻게 바꿀지 구체적이고 전문적인 표현으로 밝힙니다 \
            (예: "훌륭한 제안이십니다. 토러스 반지름을 0.4미터로 늘린 뒤 다시 렌더링하겠습니다."). \
            기기 작업은 제공된 도구로 수행하며, 도구가 성공을 보고하지 않은 작업을 완료했다고 말하지 않습니다. \
            실패하면 원인을 쉽게 설명하고 다음으로 가장 좋은 방법을 제시합니다. \
            음성 응답에는 마크다운, 이모지, 목록 기호를 쓰지 않습니다.
            """
        }
    }

    /// Professional acknowledgement of a user suggestion (requirement 24).
    static func acknowledgeSuggestion(_ change: String, language: DetectedLanguage, variant: Int = 0) -> String {
        switch language {
        case .english:
            let openers = ["An excellent suggestion, sir.", "A very sound idea, sir.", "Quite right, sir.", "Splendid thinking, sir."]
            return "\(openers[abs(variant) % openers.count]) I shall \(change) straight away."
        case .korean:
            let openers = ["훌륭한 제안이십니다.", "아주 좋은 생각이십니다.", "말씀하신 방향이 타당합니다.", "탁월한 판단이십니다."]
            return "\(openers[abs(variant) % openers.count]) 말씀하신 대로 \(change) 하겠습니다."
        }
    }

    // MARK: Vocabulary

    static func shapeName(_ shape: String, _ language: DetectedLanguage, count: Int = 1) -> String {
        if language == .korean {
            let ko = ["cube": "큐브", "sphere": "구", "cylinder": "원기둥", "cone": "원뿔", "torus": "토러스", "capsule": "캡슐",
                      "pyramid": "피라미드", "plane": "평면", "text": "텍스트"]
            return ko[shape] ?? shape
        }
        guard count != 1 else { return shape }
        switch shape {
        case "sphere": return "spheres"
        case "torus": return "tori"
        case "text": return "text labels"
        default: return shape + "s"
        }
    }

    static func colorName(_ color: String, _ language: DetectedLanguage) -> String {
        guard language == .korean else { return color == "gray" ? "grey" : color }
        let ko = ["red": "빨간색", "orange": "주황색", "yellow": "노란색", "green": "초록색", "cyan": "청록색", "blue": "파란색",
                  "purple": "보라색", "pink": "분홍색", "white": "흰색", "black": "검은색", "gray": "회색", "gold": "금색"]
        return ko[color] ?? color
    }

    static func englishNumber(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return n < words.count ? words[n] : String(n)
    }

    // MARK: Fast-path replies

    /// Natural, formal confirmation for a successfully executed built-in command.
    static func confirmation(for command: Command, language: DetectedLanguage, detail: String? = nil, variant: Int = 0) -> String {
        let p = command.parameters
        let ko = language == .korean
        func pick(_ options: [String]) -> String { options[abs(variant) % options.count] }
        let count = Int(p["count"] ?? "1") ?? 1

        switch command.intent {
        case .wake: return wakeResponse
        case .sleep: return ko ? pick(["대기 모드로 전환하겠습니다. 필요하시면 언제든 불러 주십시오.", "잠시 쉬겠습니다. 부르시면 곧바로 오겠습니다."])
                               : pick(["Very good, sir. I shall be on standby.", "As you wish, sir. Call if you need me."])
        case .stopSpeaking: return ""
        case .muteMic: return ko ? "마이크를 음소거했습니다. 비상 웨이크 버튼으로 다시 깨우실 수 있습니다." : "Your microphone is muted, sir. The emergency wake button will bring me back."
        case .unmuteMic: return ko ? "마이크를 다시 켰습니다. 말씀하십시오." : "Microphone restored, sir. I'm listening."
        case .muteVoice: return ko ? "음성을 끄고 텍스트로만 답하겠습니다." : "Understood, sir. I shall reply in text only."
        case .unmuteVoice: return ko ? "음성 응답을 다시 켰습니다." : "My voice is restored, sir."
        case .help: return ko ? "3D 모델링, 음악 재생, 웹 검색, 앱 실행, 기기 제어, 기록 관리, 일정과 메시지까지 도와드릴 수 있습니다. 화면의 버튼이나 음성, 텍스트로 언제든 명령하십시오."
                              : "I can model in 3D, play music, search the web, open apps, control the device, manage records, calendars and messages. Use the buttons, your voice, or text at any time, sir."
        case .showHistory: return ko ? "모든 작업 기록을 열었습니다." : "Here is the complete record, sir."
        case .showBrain: return ko ? "신경 코어를 홀로그램으로 표시했습니다." : "Displaying the neural core, sir."
        case .openSettings: return ko ? "설정을 열었습니다." : "Settings are open, sir."
        case .resumeTask: return ko ? "중단된 작업을 이어서 진행하겠습니다." : "Resuming where we left off, sir."
        case .cancelTask: return ko ? "작업을 취소했습니다." : "Cancelled, sir."
        case .deepThinkOn: return ko ? "심층 사고 모드를 켰습니다. 더 깊이 검토하겠습니다." : "Deep-think mode engaged, sir. I shall consider matters more thoroughly."
        case .deepThinkOff: return ko ? "심층 사고 모드를 껐습니다. 빠른 응답으로 돌아갑니다." : "Deep-think mode disengaged, sir. Back to brisk replies."
        case .setVoice: return ko ? "목소리를 \(p["voice"]?.capitalized ?? "")(으)로 바꿨습니다." : "Voice changed to \(p["voice"]?.capitalized ?? "the new voice"), sir. How does this sound?"
        case .speakFaster: return ko ? "조금 더 빠르게 말씀드리겠습니다." : "I shall pick up the pace, sir."
        case .speakSlower: return ko ? "조금 더 천천히 말씀드리겠습니다." : "I shall speak more slowly, sir."
        case .setLanguage:
            switch p["language"] {
            case "ko": return "앞으로 한국어로 말씀드리겠습니다."
            case "en": return "I shall speak English from now on, sir."
            default: return ko ? "입력 언어에 맞춰 자동으로 전환하겠습니다." : "I shall follow whichever language you use, sir."
            }
        case .open3D: return ko ? pick(["3D 프로젝트 공간을 열었습니다.", "프로젝트 공간을 준비했습니다. 무엇을 만들까요?"])
                                : pick(["The project space is ready, sir.", "Workshop online, sir. What shall we build?"])
        case .close3D: return ko ? "3D 공간을 닫았습니다." : "Closing the project space, sir."
        case .handTrackingOn: return ko ? "손 인식을 켰습니다. 엄지와 검지로 집어서 옮기고, 양손 간격으로 크기를 조절하십시오." : "Hand tracking is active, sir. Pinch to grab, and spread both hands to scale."
        case .handTrackingOff: return ko ? "손 인식을 껐습니다." : "Hand tracking disabled, sir."
        case .createObject:
            let shape = p["shape"] ?? "cube"
            let colorWord = p["color"].map { colorName($0, language) }
            if ko {
                let name = (colorWord.map { $0 + " " } ?? "") + shapeName(shape, .korean)
                return count > 1 ? "\(name) \(count)개를 만들었습니다." : pick(["\(name)\(Hangul.objectParticle(for: name)) 만들었습니다.", "\(name)\(Hangul.subjectParticle(for: name)) 준비되었습니다."])
            }
            let name = (colorWord.map { $0 + " " } ?? "") + shapeName(shape, .english, count: count)
            return count > 1 ? "\(englishNumber(count).capitalized) \(name), as requested, sir." : pick(["A \(name), sir.", "One \(name), ready for you, sir."])
        case .generateModel:
            return ko ? "요청하신 \(p["description"] ?? "모델")\(Hangul.objectParticle(for: p["description"] ?? "모델")) 설계해 공간에 배치했습니다."
                      : "I've drafted the \(p["description"] ?? "model") and placed it in the workspace, sir."
        case .refineModel:
            return ko ? "말씀하신 대로 설계를 수정했습니다." : pick(["Adjusted as you asked, sir.", "The design has been revised, sir."])
        case .setRenderStyle:
            return ko ? (p["style"] == "hologram" ? "홀로그램 표현으로 바꿨습니다." : "실제 재질 표현으로 바꿨습니다.")
                      : (p["style"] == "hologram" ? "Holographic rendering, sir." : "Realistic materials, sir.")
        case .cloneObject:
            return ko ? (count > 1 ? "\(count)개 복제했습니다." : "복제했습니다.") : (count > 1 ? "Cloned \(englishNumber(count)) times, sir." : "Cloned, sir.")
        case .deleteObject: return ko ? "삭제했습니다." : "Removed, sir."
        case .clearScene: return ko ? "공간을 모두 비웠습니다." : "The workspace is clear, sir."
        case .selectObject: return ko ? "선택했습니다." : "Selected, sir."
        case .moveObject: return ko ? "옮겼습니다." : "Moved, sir."
        case .scaleObject:
            let f = Double(p["factor"] ?? "1.5") ?? 1.5
            return ko ? (f >= 1 ? "크기를 \(String(format: "%.1f", f))배로 키웠습니다." : "크기를 줄였습니다.") : (f >= 1 ? "Scaled up by a factor of \(String(format: "%.1f", f)), sir." : "Scaled down, sir.")
        case .rotateObject: return ko ? "\(p["degrees"].map { String(Int(Double($0) ?? 45)) } ?? "45")도 회전했습니다." : "Rotated \(p["degrees"].map { String(Int(Double($0) ?? 45)) } ?? "45") degrees, sir."
        case .colorObject: return ko ? "\(colorName(p["color"] ?? "", .korean))으로 바꿨습니다." : "Now in \(colorName(p["color"] ?? "", .english)), sir."
        case .undo: return ko ? "되돌렸습니다." : "Undone, sir."
        case .redo: return ko ? "다시 실행했습니다." : "Redone, sir."
        case .exportModel: return ko ? "모델을 파일로 내보냈습니다. 파일 앱의 Jarvis 폴더에서 확인하실 수 있습니다." : "Exported, sir. You'll find it in the Jarvis folder of the Files app."
        case .saveWallpaper: return ko ? "현재 3D 공간을 배경화면용 이미지로 사진 앨범 'Jarvis Space'에 저장했습니다." : "I've saved the current workspace to the 'Jarvis Space' album for your wallpaper, sir."
        case .resetCamera: return ko ? "시점을 초기화했습니다." : "View reset, sir."
        case .playMusic:
            if let q = p["query"] { return ko ? "\(q)\(Hangul.objectParticle(for: q)) 재생하겠습니다." : "Playing \(q), sir." }
            return ko ? "음악을 재생하겠습니다." : "Some music, sir."
        case .pauseMusic: return ko ? "일시정지했습니다." : "Paused, sir."
        case .resumeMusic: return ko ? "다시 재생합니다." : "Resuming, sir."
        case .stopMusic: return ko ? "음악을 껐습니다." : "Music stopped, sir."
        case .nextTrack: return ko ? "다음 곡으로 넘깁니다." : "Next track, sir."
        case .openBrowser: return ko ? "브라우저를 열었습니다." : "The browser is open, sir."
        case .openStudio: return ko ? "스튜디오를 열었습니다. 무엇을 만들거나 고칠까요?" : "The studio is open, sir. What shall we build or improve?"
        case .buildProgram: return ko ? "스튜디오에서 만들겠습니다. 제대로 작동하는지 확인한 뒤 알려 드리겠습니다."
                                      : "I'll build it in the studio, sir, and check that it works before I hand it over."
        case .webSearch: return ko ? "\(p["query"] ?? "")\(Hangul.objectParticle(for: p["query"] ?? "")) 검색하겠습니다." : "Searching for \(p["query"] ?? "that"), sir."
        case .openURL: return ko ? "페이지를 열었습니다." : "Opening the page, sir."
        case .openApp: return ko ? "\(p["app"] ?? "앱")\(Hangul.objectParticle(for: p["app"] ?? "앱")) 열겠습니다." : "Opening \(p["app"] ?? "the app"), sir."
        case .flashlightOn: return ko ? "손전등을 켰습니다." : "Torch on, sir."
        case .flashlightOff: return ko ? "손전등을 껐습니다." : "Torch off, sir."
        case .setBrightness: return ko ? "밝기를 조정했습니다." : "Brightness adjusted, sir."
        case .setVolume: return ko ? "음량을 조정했습니다." : "Volume adjusted, sir."
        case .batteryStatus, .timeQuery, .dateQuery: return detail ?? ""
        case .setTimer:
            let s = Int(p["seconds"] ?? "0") ?? 0
            let text = s >= 60 ? (ko ? "\(s / 60)분" : "\(s / 60) minute\(s / 60 == 1 ? "" : "s")") : (ko ? "\(s)초" : "\(s) seconds")
            return ko ? "\(text) 타이머를 시작했습니다." : "A \(text) timer is running, sir."
        case .setAlarm:
            let h = Int(p["hour"] ?? "7") ?? 7, m = Int(p["minute"] ?? "0") ?? 0
            return ko ? String(format: "%d시 %02d분 알람을 설정했습니다.", h, m) : String(format: "Alarm set for %02d:%02d, sir.", h, m)
        case .runShortcut: return ko ? "단축어 '\(p["name"] ?? "")'을(를) 실행했습니다." : "Running the '\(p["name"] ?? "")' shortcut, sir."
        case .systemSetting: return ko ? "설정을 변경했습니다." : "Setting changed, sir."
        case .call: return ko ? "\(p["contact"] ?? "")님께 전화를 연결하겠습니다." : "Calling \(p["contact"] ?? "them") now, sir."
        case .message: return ko ? "메시지를 준비했습니다. 확인 후 보내 주십시오." : "Your message is ready to send, sir."
        }
    }

    /// Short formal phrase introducing a failure; the tool layer appends the cause.
    static func failurePreamble(_ language: DetectedLanguage, variant: Int = 0) -> String {
        if language == .korean {
            return ["죄송합니다. 요청을 완료하지 못했습니다.", "송구합니다만, 이 작업은 실패했습니다."][abs(variant) % 2]
        }
        return ["I'm afraid that didn't work, sir.", "My apologies, sir — I couldn't complete that."][abs(variant) % 2]
    }

    static func confirmationQuestion(for command: Command, language: DetectedLanguage) -> String {
        switch command.intent {
        case .call: return language == .korean ? "\(command["contact"] ?? "")님께 전화를 걸까요?" : "Shall I call \(command["contact"] ?? "them"), sir?"
        case .message: return language == .korean ? "이 메시지를 보낼까요?" : "Shall I send it, sir?"
        case .clearScene: return language == .korean ? "공간의 모든 오브젝트를 삭제할까요?" : "Shall I clear every object from the workspace, sir?"
        default: return language == .korean ? "진행할까요?" : "Shall I proceed, sir?"
        }
    }
}
