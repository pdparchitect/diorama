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

/// Captures the virtual display with ScreenCaptureKit and delivers frames to the stage view.
@MainActor
final class StageStream {
    private var stream: SCStream?
    private var sink: StageFrameSink?
    private(set) var pixelSize: CGSize = .zero
    var isRunning: Bool { stream != nil }

    func start(displayID: CGDirectDisplayID, pixelSize: CGSize, onFrame: @escaping @MainActor (StageFrame) -> Void, onStop: @escaping @MainActor (Error?) -> Void) async throws {
        await stop()
        let content = try await ShareableContent.current()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw DioramaError.displayNotShareable }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.queueDepth = 5
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        let sink = StageFrameSink(onFrame: onFrame, onStop: onStop)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        self.stream = stream
        self.sink = sink
        self.pixelSize = pixelSize
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        self.sink = nil
        pixelSize = .zero
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.stopCapture { _ in continuation.resume() }
        }
    }
}

enum ShareableContent {
    /// Every display and window, including those on other Spaces and displays.
    static func current() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    }
}
