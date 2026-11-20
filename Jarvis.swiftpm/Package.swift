// swift-tools-version: 5.9

// Jarvis — fully on-device agentic AI for iPad & iPhone.
// Open this package in Swift Playgrounds (iPad, 4.7+ with the iOS 26 SDK) or in Xcode.
//
// NOTE: Swift Playgrounds may rewrite this file when you change the app settings
// (name, icon, capabilities) in its UI. If that happens, re-apply the
// `additionalInfoPlistContentFilePath` line below — it enables background audio,
// the jarvis:// URL scheme, and Files-app access to Jarvis' logs.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Jarvis",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .iOSApplication(
            name: "Jarvis",
            targets: ["AppModule"],
            bundleIdentifier: "com.jarvis.local.assistant",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .sparkle),
            accentColor: .presetColor(.cyan),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .microphone(purposeString: "Jarvis listens for \"wake up Jarvis\" and your spoken commands. 음성 웨이크와 음성 명령을 듣기 위해 마이크를 사용합니다."),
                .speechRecognition(purposeString: "Jarvis transcribes your voice on-device. 음성을 기기 안에서 텍스트로 변환합니다."),
                .camera(purposeString: "Jarvis tracks your hand gestures to manipulate 3D holograms. 손동작으로 3D 홀로그램을 조작하기 위해 카메라를 사용합니다."),
                .photoLibrary(purposeString: "Jarvis reads photos you ask about and imports images into projects. 요청하신 사진을 찾고 프로젝트로 가져옵니다."),
                .photoLibraryAdd(purposeString: "Jarvis saves 3D-space snapshots for your wallpaper automation. 3D 공간 스냅샷을 배경화면용으로 저장합니다."),
                .contacts(purposeString: "Jarvis finds people you ask to call or message. 전화·메시지 대상 연락처를 찾습니다."),
                .calendars(purposeString: "Jarvis reads and creates calendar events on request. 요청 시 일정을 확인하고 만듭니다."),
                .reminders(purposeString: "Jarvis reads and creates reminders on request. 요청 시 미리 알림을 확인하고 만듭니다."),
                .locationWhenInUse(purposeString: "Jarvis uses your location for directions and local answers. 길 안내와 지역 정보에 위치를 사용합니다."),
                .bluetoothAlways(purposeString: "Jarvis connects to compatible Bluetooth accessories you ask it to control. 요청하신 블루투스 장비와 연결합니다."),
                .mediaLibrary(purposeString: "Jarvis plays music from your library on request. 요청 시 보관함의 음악을 재생합니다."),
                .motion(purposeString: "Jarvis uses motion to stabilise holograms. 홀로그램 안정화에 모션 센서를 사용합니다."),
                .localNetwork(purposeString: "Jarvis discovers compatible devices on your network. 네트워크의 호환 장비를 찾습니다."),
                .fileAccess(.userSelectedFiles, mode: .readWrite),
                .outgoingNetworkConnections()
            ],
            appCategory: .productivity,
            additionalInfoPlistContentFilePath: "Info-Extra.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
