// swift-tools-version: 5.9

// Jarvis - on-device agentic AI for iPad and iPhone (Swift Playground or Xcode).
// Keep this file plain ASCII: Swift Playground reads the evaluated manifest back
// as text, and non-ASCII characters here can make loading fail
// ("CouldNotFindNullRecordSeparator").
// If Swift Playground rewrites this file after you edit the app settings, add the
// additionalInfoPlistContentFilePath line back (background audio, jarvis:// links).

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
                .microphone(purposeString: "Jarvis listens for the wake phrase and your voice commands."),
                .speechRecognition(purposeString: "Jarvis turns your speech into text on this device."),
                .camera(purposeString: "Jarvis follows your hand gestures to move 3D objects."),
                .photoLibrary(purposeString: "Jarvis keeps a Jarvis Space album for wallpaper snapshots."),
                .photoLibraryAdd(purposeString: "Jarvis saves 3D workspace snapshots to your photos."),
                .contacts(purposeString: "Jarvis finds the people you ask it to call or message."),
                .calendars(purposeString: "Jarvis reads and adds calendar events when you ask."),
                .reminders(purposeString: "Jarvis reads and adds reminders when you ask."),
                .locationWhenInUse(purposeString: "Jarvis uses your location for directions and local answers."),
                .bluetoothAlways(purposeString: "Jarvis connects to Bluetooth accessories you ask it to use."),
                .mediaLibrary(purposeString: "Jarvis plays songs from your music library when you ask."),
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
    ],
    swiftLanguageVersions: [.v5]
)
