import XCTest
@testable import JarvisCore

final class DeadlineTests: XCTestCase {
    @MainActor
    func testReturnsTheResultInTime() async throws {
        let value = try await withDeadline(seconds: 2) { () async throws -> Int in
            try await Task.sleep(nanoseconds: 20_000_000)
            return 42
        }
        XCTAssertEqual(value, 42)
    }

    /// Design specs come back through a deadline in the app, so they must stay Sendable.
    @MainActor
    func testDesignSpecsPassThrough() async throws {
        let spec = try await withDeadline(seconds: 1) { ModelSpec(name: "box", parts: []) }
        XCTAssertEqual(spec.name, "box")
    }

    @MainActor
    func testPassesErrorsThrough() async {
        struct Boom: Error {}
        do {
            _ = try await withDeadline(seconds: 2) { () async throws -> Int in throw Boom() }
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    /// An operation that ignores cancellation (like a hung model) no longer holds the caller.
    @MainActor
    func testGivesUpOnAHungOperation() async {
        let began = Date()
        do {
            _ = try await withDeadline(seconds: 0.2) { () async -> Int in
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) { c.resume() }
                }
                return 1
            }
            XCTFail("expected a timeout")
        } catch {
            XCTAssertTrue(error is DeadlineExceeded, "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 1.5)
    }

    @MainActor
    func testCancellingTheCallerStopsWaiting() async {
        let began = Date()
        let caller = Task { @MainActor () -> Error? in
            do {
                _ = try await withDeadline(seconds: 10) { () async -> Int in
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { c.resume() }
                    }
                    return 1
                }
                return nil
            } catch {
                return error
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        caller.cancel()
        let error = await caller.value
        XCTAssertTrue(error is CancellationError, "\(String(describing: error))")
        XCTAssertLessThan(Date().timeIntervalSince(began), 2)
    }
}
