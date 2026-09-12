import AppKit
import CoreMedia
import IOSurface
import ScreenCaptureKit
import os

/// One captured frame. The sample buffer is retained alongside the surface so ScreenCaptureKit does not recycle the
/// surface while it is on screen.
struct StageFrame: @unchecked Sendable {
    let surface: IOSurface
    let sampleBuffer: CMSampleBuffer
}

/// Receives frames on the capture queue and hands the newest one to the main thread, dropping frames while one is pending.
final class StageFrameSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.pdparchitect.diorama.frames", qos: .userInteractive)
    private let pending = OSAllocatedUnfairLock(initialState: false)
    private let onFrame: @MainActor (StageFrame) -> Void
    private let onStop: @MainActor (Error?) -> Void

    init(onFrame: @escaping @MainActor (StageFrame) -> Void, onStop: @escaping @MainActor (Error?) -> Void) {
        self.onFrame = onFrame
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        let frame = StageFrame(surface: surface, sampleBuffer: sampleBuffer)
        let shouldDeliver = pending.withLock { pending -> Bool in
            if pending { return false }
            pending = true
            return true
        }
        guard shouldDeliver else { return }
        DispatchQueue.main.async { [self] in
            pending.withLock { $0 = false }
            MainActor.assumeIsolated { onFrame(frame) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { onStop(error) }
        }
    }
}

/// Small capture boundary so lifecycle races can be exercised without recording a user's screen.
@MainActor
protocol StageCaptureSession: AnyObject {
    func start() async throws
    func stop() async
}

/// Captures the virtual display and rejects callbacks belonging to a stopped or superseded session.
@MainActor
final class StageStream {
    typealias SessionFactory = @MainActor (
        CGDirectDisplayID, CGSize,
        @escaping @MainActor (StageFrame) -> Void,
        @escaping @MainActor (Error?) -> Void
    ) async throws -> any StageCaptureSession

    private let makeSession: SessionFactory
    private var session: (any StageCaptureSession)?
    private var generation = UUID()
    private(set) var pixelSize: CGSize = .zero
    private(set) var isRunning = false

    init(makeSession: @escaping SessionFactory = ScreenCaptureSession.make) {
        self.makeSession = makeSession
    }

    func start(displayID: CGDirectDisplayID, pixelSize: CGSize, onFrame: @escaping @MainActor (StageFrame) -> Void, onStop: @escaping @MainActor (Error?) -> Void) async throws {
        let token = UUID()
        generation = token
        let previous = session
        session = nil
        isRunning = false
        self.pixelSize = .zero
        await previous?.stop()
        try check(token)

        let candidate = try await makeSession(displayID, pixelSize, { [weak self] frame in
            guard let self, self.generation == token else { return }
            onFrame(frame)
        }, { [weak self] error in
            guard let self, self.generation == token else { return }
            self.generation = UUID()
            self.session = nil
            self.isRunning = false
            self.pixelSize = .zero
            onStop(error)
        })
        do {
            try check(token)
            session = candidate
            try await candidate.start()
            try check(token)
            isRunning = true
            self.pixelSize = pixelSize
        } catch {
            if generation == token {
                generation = UUID()
                session = nil
                isRunning = false
                self.pixelSize = .zero
            }
            await candidate.stop()
            throw error
        }
    }

    func stop() async {
        generation = UUID()
        let previous = session
        session = nil
        isRunning = false
        pixelSize = .zero
        await previous?.stop()
    }

    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
    }
}

@MainActor
private final class ScreenCaptureSession: StageCaptureSession {
    private let stream: SCStream
    // SCStream does not own its delegate. Keep it alive throughout capture and stop.
    private let sink: StageFrameSink

    private init(stream: SCStream, sink: StageFrameSink) {
        self.stream = stream
        self.sink = sink
    }

    static func make(displayID: CGDirectDisplayID, pixelSize: CGSize, onFrame: @escaping @MainActor (StageFrame) -> Void, onStop: @escaping @MainActor (Error?) -> Void) async throws -> any StageCaptureSession {
        let content = try await ShareableContent.current()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw DioramaError.displayNotShareable }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.queueDepth = 5
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        let sink = StageFrameSink(onFrame: onFrame, onStop: onStop)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        return ScreenCaptureSession(stream: stream, sink: sink)
    }

    func start() async throws {
        try await stream.startCapture()
    }

    func stop() async {
        try? await stream.stopCapture()
    }
}

enum ShareableContent {
    /// Every display and window, including those on other Spaces and displays.
    static func current() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    }
}
