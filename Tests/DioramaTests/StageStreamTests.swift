import AppKit
import Testing
@testable import Diorama

@Suite @MainActor
struct StageStreamTests {
    private let pixels = CGSize(width: 3840, height: 2160)

    @Test func unexpectedStopAllowsRestart() async throws {
        var sessions: [FakeCaptureSession] = []
        let stream = StageStream { _, _, _, onStop in
            let session = FakeCaptureSession(onStop: onStop)
            sessions.append(session)
            return session
        }
        var stops = 0
        try await stream.start(displayID: 1, pixelSize: pixels, onFrame: { _ in }, onStop: { _ in stops += 1 })
        #expect(stream.isRunning)
        sessions[0].onStop(TestFailure.capture)
        #expect(!stream.isRunning)
        #expect(stream.pixelSize == .zero)
        #expect(stops == 1)
        try await stream.start(displayID: 1, pixelSize: pixels, onFrame: { _ in }, onStop: { _ in stops += 1 })
        #expect(sessions.count == 2)
        #expect(stream.isRunning)
        // A queued delegate callback from the failed stream must not stop the replacement.
        sessions[0].onStop(TestFailure.capture)
        #expect(stream.isRunning)
        #expect(stops == 1)
        await stream.stop()
    }

    @Test func stopDuringStartupDoesNotResurrectCapture() async throws {
        let session = FakeCaptureSession()
        let stream = StageStream { _, _, _, _ in session }
        session.startAction = { await stream.stop() }
        do {
            try await stream.start(displayID: 1, pixelSize: pixels, onFrame: { _ in }, onStop: { _ in })
            Issue.record("A stopped startup must be cancelled")
        } catch is CancellationError { }
        #expect(!stream.isRunning)
        #expect(stream.pixelSize == .zero)
        #expect(session.stops > 0)
    }

    @Test func replacementSurvivesLateStartupCompletion() async throws {
        let first = FakeCaptureSession()
        let second = FakeCaptureSession()
        var count = 0
        let stream = StageStream { _, _, _, _ in
            count += 1
            return count == 1 ? first : second
        }
        let replacementPixels = CGSize(width: 2560, height: 1440)
        first.startAction = {
            try await stream.start(displayID: 1, pixelSize: replacementPixels, onFrame: { _ in }, onStop: { _ in })
        }
        do {
            try await stream.start(displayID: 1, pixelSize: pixels, onFrame: { _ in }, onStop: { _ in })
            Issue.record("The superseded startup must be cancelled")
        } catch is CancellationError { }
        #expect(stream.isRunning)
        #expect(stream.pixelSize == replacementPixels)
        #expect(second.stops == 0)
        await stream.stop()
    }

    @Test func failedStartupReleasesSessionAndCanRetry() async throws {
        let first = FakeCaptureSession()
        first.startAction = { throw TestFailure.capture }
        var count = 0
        let stream = StageStream { _, _, _, _ in
            count += 1
            return count == 1 ? first : FakeCaptureSession()
        }
        do {
            try await stream.start(displayID: 1, pixelSize: pixels, onFrame: { _ in }, onStop: { _ in })
            Issue.record("Expected a failed capture")
        } catch TestFailure.capture { }
        #expect(!stream.isRunning)
        #expect(first.stops == 1)
        try await stream.start(displayID: 1, pixelSize: pixels, onFrame: { _ in }, onStop: { _ in })
        #expect(stream.isRunning)
        await stream.stop()
    }
}

private enum TestFailure: Error { case capture }

@MainActor
private final class FakeCaptureSession: StageCaptureSession {
    var startAction: () async throws -> Void = {}
    let onStop: @MainActor (Error?) -> Void
    private(set) var stops = 0

    init(onStop: @escaping @MainActor (Error?) -> Void = { _ in }) { self.onStop = onStop }
    func start() async throws { try await startAction() }
    func stop() async { stops += 1 }
}
