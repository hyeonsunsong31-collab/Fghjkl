import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Records why the app died, so the next launch can say it in the chat
/// (Swift Playground only shows "Unknown Crash").
///
/// - Uncaught Objective-C exceptions (AVFoundation, Speech, …): name, reason and stack.
/// - Fatal signals (Swift traps, aborts): the signal number plus the last
///   *breadcrumb* — a short note of what the app was doing (for example
///   "audio: starting engine"), written with async-signal-safe calls only.
enum CrashLog {
    private static let crumbCapacity = 160
    private static let crumb: UnsafeMutablePointer<CChar> = {
        let p = UnsafeMutablePointer<CChar>.allocate(capacity: 160)
        p.initialize(repeating: 0, count: 160)
        return p
    }()
    private static var fileDescriptor: Int32 = -1
    private static var installed = false
    /// What ended the previous session, read at launch (nil if it ended normally).
    private(set) static var previousReport: String?

    static var fileURL: URL { JarvisPaths.logs.appendingPathComponent("last-crash.txt") }

    /// Note what the app is about to do (cheap; call before risky platform work).
    static func breadcrumb(_ text: String) {
        let bytes = Array(text.utf8.prefix(crumbCapacity - 1))
        for (i, b) in bytes.enumerated() { crumb[i] = CChar(bitPattern: b) }
        crumb[bytes.count] = 0
    }

    /// The last breadcrumb (for diagnostics such as the main-thread stall monitor).
    static var lastBreadcrumb: String { String(cString: crumb) }

    /// The previous session's crash report (removed once read); nil when it ended normally.
    static func takeLastReport() -> String? {
        let url = fileURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: url)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Call once at launch: keeps the previous report (also as Logs/previous-crash.txt
    /// for the Files app), then arms the recorders for this session.
    static func install() {
        guard !installed else { return }
        installed = true
        if let report = takeLastReport() {
            previousReport = report
            try? report.write(to: JarvisPaths.logs.appendingPathComponent("previous-crash.txt"), atomically: true, encoding: .utf8)
        }
        _ = crumb // allocate now, never inside a signal handler
        fileDescriptor = open(fileURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)

        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.prefix(30).joined(separator: "\n")
            let text = "Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "(no reason)")\n"
                + "While: \(String(cString: CrashLog.crumb))\n\(stack)\n"
            print("JARVIS CRASH: \(text)")
            CrashLog.writeRaw(text)
        }
        for sig in [SIGABRT, SIGTRAP, SIGSEGV, SIGBUS, SIGILL, SIGFPE] {
            signal(sig) { signalNumber in
                CrashLog.writeSignal(signalNumber)
                signal(signalNumber, SIG_DFL)
                raise(signalNumber)
            }
        }
    }

    private static func writeRaw(_ text: String) {
        guard fileDescriptor >= 0 else { return }
        var copy = text
        copy.withUTF8 { buffer in
            if let base = buffer.baseAddress { _ = Darwin.write(fileDescriptor, base, buffer.count) }
        }
    }

    /// Async-signal-safe: fixed strings, the pre-allocated breadcrumb and write(2) only.
    private static func writeSignal(_ number: Int32) {
        let fd = fileDescriptor
        guard fd >= 0 else { return }
        let header: StaticString = "Fatal signal "
        _ = Darwin.write(fd, header.utf8Start, header.utf8CodeUnitCount)
        var digits: (CChar, CChar, CChar) = (0, 0, 0)
        let n = max(0, min(99, Int(number)))
        digits.0 = CChar(48 + n / 10)
        digits.1 = CChar(48 + n % 10)
        digits.2 = 10
        withUnsafePointer(to: &digits) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 3) { _ = Darwin.write(fd, $0, 3) }
        }
        let label: StaticString = "While: "
        _ = Darwin.write(fd, label.utf8Start, label.utf8CodeUnitCount)
        _ = Darwin.write(fd, crumb, strlen(crumb))
        let newline: StaticString = "\n"
        _ = Darwin.write(fd, newline.utf8Start, newline.utf8CodeUnitCount)
    }
}
