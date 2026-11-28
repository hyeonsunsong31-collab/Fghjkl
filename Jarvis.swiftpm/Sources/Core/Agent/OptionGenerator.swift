import Foundation

/// Proposes follow-up adjustment options (2-(3)) and recommendations (2-(4))
/// for built-in commands. Each option carries an utterance that the grammar
/// can execute, so tapping an option = saying it.
struct OptionGenerator {
    func options(after command: Command, language ko: DetectedLanguage, success: Bool) -> ([SuggestedOption], [Recommendation]) {
        let k = ko == .korean
        func o(_ en: String, _ kr: String) -> SuggestedOption {
            SuggestedOption(label: k ? kr : en, utterance: k ? kr : en.lowercased())
        }
        func r(_ en: String, _ kr: String, _ uen: String? = nil, _ ukr: String? = nil) -> Recommendation {
            Recommendation(text: k ? kr : en, utterance: k ? ukr : uen)
        }

        guard success else {
            return ([o("Try again", "다시 시도"), o("Show history", "기록 보여줘")],
                    [r("I can explain what went wrong in detail if you ask, sir.", "원하시면 실패 원인을 자세히 설명해 드리겠습니다.")])
        }

        switch command.intent {
        case .open3D:
            return ([o("Make a cube", "큐브 만들어"), o("Enable hand tracking", "손 인식 켜"), o("Build a helmet", "헬멧 만들어")],
                    [r("Try sculpting with your hands: pinch to grab, spread both hands to scale.", "손으로 조작해 보십시오. 집어서 옮기고, 양손 간격으로 크기를 바꿀 수 있습니다.", "enable hand tracking", "손 인식 켜")])
        case .generateModel, .refineModel:
            return ([o("Make the main colour gold", "전체를 금색으로 바꿔"), o("Make it bigger", "더 크게 만들어"), o("Hologram mode", "홀로그램 모드")],
                    [r("Refine any part by name, e.g. 'make the wheels gold', 'add a chimney' or 'remove the spoiler'.",
                       "부품 이름으로 고칠 수 있습니다. 예: '바퀴를 금색으로 바꿔', '굴뚝 추가해', '스포일러 빼줘'.")])
        case .createObject:
            return ([o("Make it bigger", "더 크게 만들어"), o("Clone it", "복제해"), o("Change colour to gold", "금색으로 바꿔")],
                    [r("Save it as your wallpaper once you're happy with the composition.", "구도가 마음에 드시면 배경화면으로 저장해 보십시오.", "set as wallpaper", "배경화면으로 저장해")])
        case .cloneObject:
            return ([o("Move it right", "오른쪽으로 옮겨"), o("Clone again", "한 번 더 복제해"), o("Undo", "되돌려")],
                    [r("Arrange clones in a row by moving each one right.", "복제본을 오른쪽으로 하나씩 옮기면 일렬로 배치됩니다.")])
        case .scaleObject, .moveObject, .rotateObject, .colorObject:
            return ([o("Undo", "되돌려"), o("Rotate it 45 degrees", "45도 회전해"), o("Export the model", "모델 내보내기")],
                    [r("Export to USDZ to view it in AR Quick Look.", "USDZ로 내보내면 AR 빠른 보기로 확인하실 수 있습니다.", "export the model", "모델 내보내기")])
        case .playMusic, .resumeMusic:
            return ([o("Pause", "일시정지"), o("Next song", "다음 곡"), o("Turn the volume down", "볼륨 줄여")],
                    [r("Say 'pause' at any time; I'll keep listening while the music plays.", "음악이 나오는 동안에도 '일시정지'라고 말씀하시면 됩니다.")])
        case .webSearch, .openURL, .openBrowser:
            return ([o("Summarise this page", "이 페이지 요약해"), o("Open the first result", "첫 번째 결과 열어"), o("Search again", "다시 검색해")],
                    [r("I can read the page aloud or summarise it for you, sir.", "페이지를 요약하거나 읽어 드릴 수 있습니다.", "summarise this page", "이 페이지 요약해")])
        case .muteMic:
            return ([o("Unmute the mic", "마이크 켜")],
                    [r("The emergency wake button stays on screen while the mic is muted.", "마이크가 꺼져 있어도 비상 웨이크 버튼은 항상 화면에 있습니다.")])
        case .deepThinkOn:
            return ([o("Deep think off", "심층 사고 꺼")],
                    [r("Deep think uses more battery; I'll switch back automatically when the battery is low.", "심층 사고는 배터리를 더 사용하므로, 배터리가 부족하면 자동으로 전환하겠습니다.")])
        case .setTimer, .setAlarm:
            return ([o("Show history", "기록 보여줘")], [])
        default:
            return ([], [])
        }
    }
}
