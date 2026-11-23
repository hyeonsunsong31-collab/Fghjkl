@preconcurrency import AVFoundation
import Vision
import UIKit
import Observation

/// Camera hand tracking (front camera + Vision hand-pose) that drives the 3D
/// space like a holographic workshop: pinch with thumb and index to grab and
/// drag, pinch with both hands and spread/close them to scale, twist to rotate.
/// Can be switched off by button or voice ("hand tracking off" / "손 인식 꺼").
@MainActor
@Observable
final class HandTrackingService: NSObject {
    var isRunning = false
    var status = ""
    /// Normalised (0…1, mirrored) fingertip points for the on-screen hand overlay.
    var overlayPoints: [CGPoint] = []
    var pinching = false

    @ObservationIgnored var onEvents: (([HandGestureEvent]) -> Void)?
    @ObservationIgnored private let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCaptureVideoDataOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "jarvis.handtracking")
    @ObservationIgnored private var configured = false
    @ObservationIgnored private let processor = HandPoseProcessor()

    func start() async {
        guard !isRunning else { return }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else {
            status = "Camera permission denied"
            return
        }
        if !configured { configure() }
        guard configured else { return }
        processor.onResult = { @Sendable [weak self] (hands: [HandLandmarks], time: Double) in
            Task { @MainActor in self?.handle(hands, time: time) }
        }
        let s = session
        queue.async { s.startRunning() }
        isRunning = true
        status = ""
    }

    func stop() {
        guard isRunning else { return }
        let s = session
        queue.async { s.stopRunning() }
        isRunning = false
        overlayPoints = []
        onEvents?([.handsLost])
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            status = "No camera available"
            return
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(processor, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        if let connection = output.connection(with: .video) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            processor.rotationCoordinator = coordinator
            processor.connection = connection
        }
        session.commitConfiguration()
        configured = true
    }

    private var interpreter = HandGestureInterpreter(mirrored: true)

    private func handle(_ hands: [HandLandmarks], time: Double) {
        var points: [CGPoint] = []
        for h in hands {
            for p in [h.thumbTip, h.indexTip, h.wrist, h.middleMCP] {
                points.append(CGPoint(x: 1 - p.x, y: p.y))
            }
        }
        overlayPoints = points
        let events = interpreter.process(hands, time: time)
        pinching = events.contains { e in
            switch e {
            case .grabBegan, .grabMoved, .twoHandBegan, .twoHandScale, .twoHandRotate: return true
            default: return false
            }
        }
        if !events.isEmpty { onEvents?(events) }
    }
}

/// Runs Vision on camera frames off the main thread.
final class HandPoseProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onResult: (@Sendable ([HandLandmarks], Double) -> Void)?
    var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    weak var connection: AVCaptureConnection?
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private var frame = 0

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frame += 1
        if frame % 60 == 0, let c = rotationCoordinator {
            let angle = c.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
        }
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        var hands: [HandLandmarks] = []
        for observation in request.results ?? [] {
            guard let thumb = try? observation.recognizedPoint(.thumbTip),
                  let index = try? observation.recognizedPoint(.indexTip),
                  let wrist = try? observation.recognizedPoint(.wrist),
                  let middle = try? observation.recognizedPoint(.middleMCP) else { continue }
            let minConfidence = min(thumb.confidence, index.confidence, wrist.confidence, middle.confidence)
            guard minConfidence > 0.3 else { continue }
            // Vision uses a bottom-left origin; convert to top-left.
            func p(_ v: VNRecognizedPoint) -> Point2 { Point2(x: Double(v.location.x), y: 1 - Double(v.location.y)) }
            let chirality: String?
            switch observation.chirality {
            case .left: chirality = "left"
            case .right: chirality = "right"
            default: chirality = nil
            }
            hands.append(HandLandmarks(thumbTip: p(thumb), indexTip: p(index), wrist: p(wrist), middleMCP: p(middle),
                                       confidence: Double(minConfidence), chirality: chirality))
        }
        onResult?(hands, time.isFinite ? time : CACurrentMediaTime())
    }
}
