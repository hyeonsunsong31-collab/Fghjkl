import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Keeps Jarvis present when you leave the app:
/// - the audio session stays active (UIBackgroundModes: audio) so wake-word
///   listening continues in the background (best effort — iOS decides);
/// - a **floating Picture-in-Picture hologram** shows Jarvis' status over other
///   apps; its play/pause button toggles listening, "restore" returns to the HUD.
@MainActor
final class PresenceManager: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    static let shared = PresenceManager()

    let displayLayer = AVSampleBufferDisplayLayer()
    private var pip: AVPictureInPictureController?
    private var renderTask: Task<Void, Never>?
    private var awake = false
    var pipEnabled: Bool {
        get { RecordKeeper.shared.setting("pipEnabled") != "0" }
        set {
            RecordKeeper.shared.setSetting("pipEnabled", newValue ? "1" : "0")
            pip?.canStartPictureInPictureAutomaticallyFromInline = newValue
        }
    }

    private override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didEnterBackground() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.willEnterForeground() }
        }
    }

    /// Called once the PiP source layer is in the view hierarchy.
    func configurePiP() {
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        CrashLog.breadcrumb("pip: configure")
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = pipEnabled
        pip = controller
        startRendering()
    }

    func awakeStateChanged(_ isAwake: Bool) {
        awake = isAwake
        refresh()
    }

    func refresh() { renderFrame() }

    private func didEnterBackground() {
        JarvisController.shared.saveBrain()
        BackgroundTasks.schedule()
    }

    private func willEnterForeground() {
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
    }

    // MARK: Rendering the hologram into the PiP layer

    private func startRendering() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.renderFrame()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private var frameIndex = 0
    /// Mirror of the mic state readable from any thread (AVKit may query off the main thread).
    nonisolated(unsafe) private static var pausedFlag = false

    private func renderFrame() {
        frameIndex += 1
        let jarvis = JarvisController.shared
        Self.pausedFlag = jarvis.micMuted
        let state = HologramFrameState(phase: jarvis.phase, micMuted: jarvis.micMuted, isAwake: jarvis.isAwake,
                                       inputLevel: CGFloat(jarvis.inputLevel), time: CGFloat(frameIndex) * 0.2)
        let size = CGSize(width: 480, height: 270)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image: UIImage = renderer.image { (ctx: UIGraphicsImageRendererContext) in
            Self.drawHologram(in: ctx.cgContext, size: size, state: state)
        }
        if let buffer = Self.sampleBuffer(from: image) {
            displayLayer.sampleBufferRenderer.enqueue(buffer)
        }
    }

    /// Everything the PiP frame shows (kept as plain values so drawing needs no actor hops).
    private struct HologramFrameState {
        let phase: AssistantPhase
        let micMuted: Bool
        let isAwake: Bool
        let inputLevel: CGFloat
        let time: CGFloat
    }

    private static func phaseColor(_ phase: AssistantPhase) -> UIColor {
        switch phase {
        case .asleep: return UIColor(white: 0.75, alpha: 0.8)
        case .listening: return UIColor(red: 0, green: 0.9, blue: 1, alpha: 1)
        case .thinking: return UIColor(red: 1, green: 0.72, blue: 0.25, alpha: 1)
        case .speaking: return UIColor.white
        }
    }

    private static func statusText(_ state: HologramFrameState) -> String {
        switch state.phase {
        case .asleep: return state.micMuted ? "MIC OFF" : "STANDBY"
        case .listening: return "LISTENING"
        case .thinking: return "THINKING"
        case .speaking: return "SPEAKING"
        }
    }

    // Small, explicitly typed statements: older Swift compilers (such as the one in
    // Swift Playground) time out type-checking one big drawing closure.
    private static func drawHologram(in cg: CGContext, size: CGSize, state: HologramFrameState) {
        UIColor(red: 0.01, green: 0.03, blue: 0.08, alpha: 1).setFill()
        cg.fill(CGRect(origin: .zero, size: size))
        let center = CGPoint(x: 120, y: size.height / 2)
        let color: UIColor = phaseColor(state.phase)
        cg.setLineCap(.round)
        let radii: [CGFloat] = [90, 72, 56]
        let segmentCounts: [Int] = [6, 18, 3]
        let speeds: [CGFloat] = [0.4, -0.7, 1.2]
        let ringColor: CGColor = color.withAlphaComponent(0.85).cgColor
        for ring in 0..<radii.count {
            let segments: Int = segmentCounts[ring]
            let arcLength: CGFloat = (2 * CGFloat.pi / CGFloat(segments)) * 0.65
            cg.setLineWidth(ring == 2 ? 6 : 3)
            for segment in 0..<segments {
                let fraction: CGFloat = CGFloat(segment) / CGFloat(segments)
                let start: CGFloat = fraction * 2 * CGFloat.pi + state.time * speeds[ring]
                cg.setStrokeColor(ringColor)
                cg.addArc(center: center, radius: radii[ring], startAngle: start, endAngle: start + arcLength, clockwise: false)
                cg.strokePath()
            }
        }
        let pulse: CGFloat = 6 * sin(state.time * 2)
        let inner: CGFloat = 30 + pulse + state.inputLevel * 18
        let gradientColors: [CGColor] = [UIColor.white.cgColor, color.cgColor, color.withAlphaComponent(0).cgColor]
        let locations: [CGFloat] = [0, 0.5, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors as CFArray, locations: locations) {
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: inner * 1.8, options: [])
        }
        drawText("J.A.R.V.I.S", size: 26, weight: .bold, color: color, at: CGPoint(x: 240, y: 70))
        drawText(statusText(state), size: 18, weight: .semibold, color: UIColor(white: 0.9, alpha: 1), at: CGPoint(x: 240, y: 112))
        let hint: String = state.isAwake ? "\u{25B6}\u{FE0E}/\u{275A}\u{275A} mic \u{00B7} \u{2922} open" : "say \u{201C}Wake up Jarvis\u{201D}"
        drawText(hint, size: 13, weight: .regular, color: UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 0.8), at: CGPoint(x: 240, y: 150))
    }

    private static func drawText(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: point)
    }

    private static func sampleBuffer(from image: UIImage) -> CMSampleBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                                      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pb = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(pb, [])

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 5),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    // MARK: AVPictureInPictureSampleBufferPlaybackDelegate

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in
            let jarvis = JarvisController.shared
            jarvis.setMicMuted(!playing)
            if playing && !jarvis.isAwake { jarvis.wake(source: .button) }
            self.renderFrame()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        Self.pausedFlag
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: AVPictureInPictureControllerDelegate

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            JarvisController.shared.wake(source: .button, speak: false)
            completionHandler(true)
        }
    }
}

/// The on-screen tile that hosts the PiP source layer (it becomes the floating hologram).
struct PresenceTile: UIViewRepresentable {
    func makeUIView(context: Context) -> PresenceLayerView {
        let v = PresenceLayerView()
        v.layer.cornerRadius = 10
        v.layer.masksToBounds = true
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor(red: 0, green: 0.9, blue: 1, alpha: 0.45).cgColor
        return v
    }

    func updateUIView(_ uiView: PresenceLayerView, context: Context) {}
}

final class PresenceLayerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        MainActor.assumeIsolated {
            let layer = PresenceManager.shared.displayLayer
            if layer.superlayer !== self.layer {
                layer.removeFromSuperlayer()
                self.layer.addSublayer(layer)
            }
            layer.frame = bounds
            PresenceManager.shared.configurePiP()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        MainActor.assumeIsolated { PresenceManager.shared.displayLayer.frame = bounds }
    }
}
