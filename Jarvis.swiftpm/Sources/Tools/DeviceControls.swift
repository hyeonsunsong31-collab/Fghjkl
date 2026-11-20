import AVFoundation
import MediaPlayer
import UIKit
import UserNotifications

/// Direct device controls available to a sandboxed app.
@MainActor
enum DeviceControls {
    // MARK: Torch

    static func setTorch(_ on: Bool) -> (Bool, String) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return (false, "This device has no torch.")
        }
        do {
            try device.lockForConfiguration()
            if on { try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { device.torchMode = .off }
            device.unlockForConfiguration()
            return (true, "")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: Brightness

    static var currentScreen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen
    }

    static func setBrightness(level: Double?, delta: Double?) -> Double {
        guard let screen = currentScreen else { return 0 }
        var value = Double(screen.brightness)
        if let level { value = level }
        if let delta { value += delta }
        value = max(0, min(1, value))
        screen.brightness = CGFloat(value)
        return value
    }

    // MARK: Volume (system volume slider; the only way an app can set output volume)

    private static let volumeView: MPVolumeView = {
        let v = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
        v.alpha = 0.01
        return v
    }()

    /// Must be called once with a window so the hidden volume slider is in the hierarchy.
    static func installVolumeView(in window: UIWindow) {
        if volumeView.superview == nil { window.addSubview(volumeView) }
    }

    static func setVolume(level: Double?, delta: Double?) -> Double {
        let current = Double(AVAudioSession.sharedInstance().outputVolume)
        var value = current
        if let level { value = level }
        if let delta { value += delta }
        value = max(0, min(1, value))
        if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
            slider.setValue(Float(value), animated: false)
            slider.sendActions(for: .valueChanged)
        }
        return value
    }

    // MARK: Status

    static func batteryDescription(_ language: DetectedLanguage) -> String {
        let body = DeviceState.body()
        let pct = Int((body.batteryLevel * 100).rounded())
        if language == .korean {
            return "배터리는 \(pct)퍼센트입니다" + (body.isCharging ? ", 충전 중입니다." : ".")
        }
        return "The battery is at \(pct) per cent" + (body.isCharging ? " and charging, sir." : ", sir.")
    }

    static func timeDescription(_ language: DetectedLanguage) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language == .korean ? "ko_KR" : "en_GB")
        f.dateFormat = language == .korean ? "a h시 m분" : "h:mm a"
        return language == .korean ? "지금은 \(f.string(from: Date()))입니다." : "It's \(f.string(from: Date())), sir."
    }

    static func dateDescription(_ language: DetectedLanguage) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language == .korean ? "ko_KR" : "en_GB")
        f.dateFormat = language == .korean ? "M월 d일 EEEE" : "EEEE d MMMM"
        return language == .korean ? "오늘은 \(f.string(from: Date()))입니다." : "Today is \(f.string(from: Date())), sir."
    }

    // MARK: Timers & alarms (local notifications)

    static func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func scheduleTimer(seconds: Int, language: DetectedLanguage) async -> Bool {
        guard seconds > 0, await requestNotificationPermission() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Jarvis"
        content.body = language == .korean ? "타이머가 끝났습니다." : "Your timer has finished, sir."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "timer-\(UUID().uuidString)", content: content, trigger: trigger)
        return (try? await UNUserNotificationCenter.current().add(request)) != nil
    }

    static func scheduleAlarm(hour: Int, minute: Int, language: DetectedLanguage) async -> Bool {
        guard await requestNotificationPermission() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Jarvis"
        content.body = language == .korean ? "알람 시간입니다." : "Good morning, sir. It's time."
        content.sound = .default
        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
        let request = UNNotificationRequest(identifier: "alarm-\(hour)-\(minute)", content: content, trigger: trigger)
        return (try? await UNUserNotificationCenter.current().add(request)) != nil
    }
}
