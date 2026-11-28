import Foundation

/// The operation did not finish in time.
struct DeadlineExceeded: Error, CustomStringConvertible {
    let seconds: Double
    var description: String { "no answer within \(Int(seconds.rounded())) s" }
}

/// Runs `operation` and returns its result, or throws `DeadlineExceeded` after `seconds` — at
/// once, even when the operation ignores cancellation (it is cancelled and left behind).
/// Cancelling the caller cancels the operation too.
///
/// A hung on-device model must never hang a whole turn: the user would see "working on it"
/// forever, and every voice command queued behind the turn would wait with it.
@MainActor
func withDeadline<T: Sendable>(seconds: Double, _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
    let race = DeadlineRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            guard race.arm(continuation) else { return }
            let work = Task { @MainActor in
                do {
                    let value = try await operation()
                    race.finish(.success(value))
                } catch {
                    race.finish(.failure(error))
                }
            }
            let timer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                race.finish(.failure(DeadlineExceeded(seconds: seconds)))
            }
            race.attach([work, timer])
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

/// One `withDeadline` call: whichever of the operation, the timer or a cancellation finishes
/// first resumes the caller; the rest is cancelled.
final class DeadlineRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    /// The result when the race ended before the caller started waiting (cancelled early).
    private var early: Result<T, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var finished = false

    /// Start waiting. False when the race had already ended (the caller is resumed at once).
    func arm(_ c: CheckedContinuation<T, Error>) -> Bool {
        lock.lock()
        if finished, let early {
            lock.unlock()
            c.resume(with: early)
            return false
        }
        continuation = c
        lock.unlock()
        return true
    }

    func attach(_ started: [Task<Void, Never>]) {
        lock.lock()
        let done = finished
        if !done { tasks = started }
        lock.unlock()
        if done { started.forEach { $0.cancel() } }
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let c = continuation
        continuation = nil
        if c == nil { early = result }
        let pending = tasks
        tasks = []
        lock.unlock()
        pending.forEach { $0.cancel() }
        c?.resume(with: result)
    }
}
