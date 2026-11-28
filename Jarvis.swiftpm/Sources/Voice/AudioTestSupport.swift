import AVFoundation

/// CI helpers for testing real speech recognition without a microphone: a sentence spoken by
/// the system voice, cut into microphone-sized buffers and surrounded by quiet room noise, is
/// fed to the recognisers in place of the microphone (`SpeechInputService.feedTestAudio`).
@MainActor
enum AudioTestSupport {
    struct Clip {
        var buffers: [AVAudioPCMBuffer]
        var speechSeconds: Double
    }

    /// `text` spoken by the best system voice for `language`, as 1024-frame mono float buffers
    /// with 1 s of quiet before and 2.5 s after (so the level detector sees the speech end).
    static func microphoneLikeClip(_ text: String, language: DetectedLanguage) async -> Clip {
        let rendered = await render(text, language: language)
        guard rendered.rate > 0, !rendered.samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: rendered.rate, channels: 1) else {
            return Clip(buffers: [], speechSeconds: 0)
        }
        func quiet(_ seconds: Double) -> [Float] {
            (0..<Int(seconds * rendered.rate)).map { _ in Float.random(in: -0.0006...0.0006) }
        }
        let all: [Float] = quiet(1.0) + rendered.samples + quiet(2.5)
        var buffers: [AVAudioPCMBuffer] = []
        var start = 0
        while start < all.count {
            let n = min(1024, all.count - start)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
                  let channel = buffer.floatChannelData else { break }
            buffer.frameLength = AVAudioFrameCount(n)
            all.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { channel[0].update(from: base + start, count: n) }
            }
            buffers.append(buffer)
            start += n
        }
        return Clip(buffers: buffers, speechSeconds: Double(rendered.samples.count) / rendered.rate)
    }

    /// Render speech to mono float samples (nothing is played).
    private static func render(_ text: String, language: DetectedLanguage) async -> (samples: [Float], rate: Double) {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = SpeechOutputService.bestVoice(for: language)
        let collector = SampleCollector()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            collector.arm(c)
            // @Sendable: the synthesizer calls this on its own queue.
            synthesizer.write(utterance) { @Sendable (buffer: AVAudioBuffer) in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    collector.finish()
                } else {
                    collector.add(pcm)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { collector.finish() }
        }
        withExtendedLifetime(synthesizer) {}
        return collector.result
    }
}

/// Collects rendered speech as mono float samples (any thread).
private final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var samples: [Float] = []
    private var rate: Double = 0

    var result: (samples: [Float], rate: Double) {
        lock.lock(); defer { lock.unlock() }
        return (samples, rate)
    }

    func arm(_ c: CheckedContinuation<Void, Never>) {
        lock.lock(); continuation = c; lock.unlock()
    }

    func add(_ pcm: AVAudioPCMBuffer) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate, channels: 1) else { return }
        let converted: AVAudioPCMBuffer? = pcm.format == format ? pcm : AudioEngineHub.convert(pcm, to: format)
        guard let converted, let data = converted.floatChannelData else { return }
        let chunk = Array(UnsafeBufferPointer(start: data[0], count: Int(converted.frameLength)))
        lock.lock()
        if rate == 0 { rate = format.sampleRate }
        if format.sampleRate == rate { samples += chunk }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume()
    }
}
