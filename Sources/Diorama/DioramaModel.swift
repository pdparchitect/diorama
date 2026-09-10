import AppKit
import SwiftUI
import DioramaCore

/// Coordinates the virtual display, the capture stream, the pointer bridge and the window actions behind the stage window.
@MainActor
final class DioramaModel: ObservableObject {
    @Published private(set) var status = "Starting…"
    @Published private(set) var captured = false
    @Published private(set) var streaming = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var displayBounds = CGRect.zero
    @Published private(set) var displayPointSize = StageResolution.default.pointSize
    @Published private(set) var lastScreenshot: URL?
    @Published private(set) var displayError: String?

    @Published var interactive = true {
        didSet {
            UserDefaults.standard.set(interactive, forKey: Self.interactiveKey)
            pushFence()
            status = interactive ? "Interactive: move the pointer into the picture to work inside Diorama." : "View only: the pointer stays on your screen."
        }
    }

    @Published var resolution: StageResolution {
        didSet {
            guard resolution != oldValue else { return }
            UserDefaults.standard.set(resolution.id, forKey: Self.resolutionKey)
            if display.exists, !display.apply(resolution) { status = "That resolution is not available on the virtual display." }
        }
    }

    private static let interactiveKey = "Interactive"
    private static let resolutionKey = "Resolution"

    private let display = VirtualDisplayController()
    private let stream = StageStream()
    private let bridge = InputBridge()
    private weak var stageView: StageNSView?
    private var stageRect: CGRect?
    private var stageWindowNumber = 0
    private var timer: Timer?
    private var startingStream = false
    private var started = false

    init() {
        let defaults = UserDefaults.standard
        interactive = defaults.object(forKey: Self.interactiveKey) as? Bool ?? true
        resolution = defaults.string(forKey: Self.resolutionKey).flatMap(StageResolution.named) ?? .default
        accessibilityGranted = Permissions.accessibility
        screenRecordingGranted = Permissions.screenRecording
        bridge.onTransition = { [weak self] transition in
            self?.captured = transition == .entered
        }
        bridge.onHotkey = { [weak self] hotkey in
            self?.perform(hotkey)
        }
    }

    var mainDisplayBounds: CGRect { CGDisplayBounds(CGMainDisplayID()) }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        if !screenRecordingGranted { Permissions.requestScreenRecording() }
        if !accessibilityGranted { Permissions.requestAccessibility() }
        do {
            try display.create()
            display.apply(resolution)
        } catch {
            displayError = error.localizedDescription
            status = error.localizedDescription
        }
        _ = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplay() }
        }
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    private func shutdown() {
        timer?.invalidate()
        bridge.uninstall()
        Task { await stream.stop() }
        display.destroy()
    }

    func attach(_ view: StageNSView) {
        stageView = view
        view.displayPointSize = displayPointSize
    }

    func stageGeometryChanged(stage: CGRect?, windowNumber: Int) {
        stageRect = stage
        stageWindowNumber = windowNumber
        pushFence()
    }

    private func poll() {
        let accessibility = Permissions.accessibility
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        let screenRecording = Permissions.screenRecording
        if screenRecording != screenRecordingGranted { screenRecordingGranted = screenRecording }
        if accessibilityGranted, !bridge.isInstalled {
            if bridge.install() {
                pushFence()
                status = interactive ? "Interactive: move the pointer into the picture to work inside Diorama." : "View only: the pointer stays on your screen."
            }
        }
        refreshDisplay()
    }

    private func refreshDisplay() {
        let bounds = display.bounds
        if bounds != displayBounds {
            displayBounds = bounds
            if !bounds.isEmpty {
                displayPointSize = bounds.size
                stageView?.displayPointSize = bounds.size
            }
        }
        if let current = display.currentResolution, current != resolution { resolution = current }
        pushFence()
        ensureStream()
    }

    private func pushFence() {
        let geometry: StageGeometry? = if let stageRect, !displayBounds.isEmpty { StageGeometry(stage: stageRect, display: displayBounds) } else { nil }
        bridge.stageWindowNumber = stageWindowNumber
        bridge.update(geometry: geometry, virtualBounds: displayBounds.isEmpty ? nil : displayBounds, physicalBounds: display.otherDisplayBounds(), interactive: interactive)
        if captured != bridge.isCaptured { captured = bridge.isCaptured }
    }

    private func ensureStream() {
        guard screenRecordingGranted, !displayBounds.isEmpty, !startingStream else { return }
        let pixelSize = display.pixelSize
        guard pixelSize.width > 0, !stream.isRunning || stream.pixelSize != pixelSize else { return }
        startingStream = true
        streaming = false
        Task {
            defer { startingStream = false }
            do {
                try await stream.start(displayID: display.displayID, pixelSize: pixelSize, onFrame: { [weak self] frame in
                    self?.stageView?.present(frame)
                }, onStop: { [weak self] error in
                    self?.streaming = false
                    self?.status = error.map { "Capture stopped: \($0.localizedDescription)" } ?? "Capture stopped."
                })
                streaming = true
            } catch {
                status = "Cannot capture the virtual display: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Actions

    func perform(_ hotkey: Hotkey) {
        switch hotkey {
        case .sendFrontWindow: sendFrontWindow()
        case .returnFrontWindow: returnFrontWindow()
        case .returnAllWindows: returnAllWindows()
        case .saveScreenshot: saveScreenshot()
        case .toggleInteractive: interactive.toggle()
        }
    }

    func releasePointer() {
        bridge.releaseCapture()
        captured = false
    }

    func sendFrontWindow() {
        guard requireAccessibility(), requireDisplay() else { return }
        guard let placement = WindowMover.frontWindow() else {
            status = DioramaError.noFrontWindow.localizedDescription
            return
        }
        let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "The"
        if displayBounds.contains(placement.frame.origin) {
            status = "\(name) window is already in Diorama."
        } else if WindowMover.move(placement, to: displayBounds) {
            status = "Sent \(name) window to Diorama."
        } else {
            status = "\(name) did not allow its window to be moved."
        }
    }

    func returnFrontWindow() {
        guard requireAccessibility(), requireDisplay() else { return }
        guard let placement = WindowMover.frontWindow() else {
            status = DioramaError.noFrontWindow.localizedDescription
            return
        }
        let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "The"
        guard displayBounds.contains(placement.frame.origin) else {
            status = "\(name) window is not in Diorama."
            return
        }
        status = WindowMover.move(placement, to: mainDisplayBounds) ? "Returned \(name) window." : "\(name) did not allow its window to be moved."
    }

    func returnAllWindows() {
        guard requireAccessibility(), requireDisplay() else { return }
        let placements = WindowMover.windows(inside: displayBounds)
        var moved = 0
        for placement in placements where WindowMover.move(placement, to: mainDisplayBounds) { moved += 1 }
        status = moved == 0 ? "No windows in Diorama." : "Returned \(moved) window\(moved == 1 ? "" : "s")."
    }

    func saveScreenshot() {
        guard requireScreenRecording(), requireDisplay() else { return }
        Task {
            do {
                let image = try await Screenshots.capture(displayID: display.displayID, pixelSize: display.pixelSize)
                let url = try Screenshots.save(image)
                lastScreenshot = url
                status = "Saved \(url.lastPathComponent) in Pictures › Diorama."
            } catch {
                status = "Screenshot failed: \(error.localizedDescription)"
            }
        }
    }

    func copyScreenshot() {
        guard requireScreenRecording(), requireDisplay() else { return }
        Task {
            do {
                let image = try await Screenshots.capture(displayID: display.displayID, pixelSize: display.pixelSize)
                try Screenshots.copy(image)
                status = "Copied a screenshot of Diorama to the clipboard."
            } catch {
                status = "Screenshot failed: \(error.localizedDescription)"
            }
        }
    }

    func showScreenshots() {
        let directory = Screenshots.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let lastScreenshot, FileManager.default.fileExists(atPath: lastScreenshot.path) {
            NSWorkspace.shared.activateFileViewerSelecting([lastScreenshot])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }

    private func requireDisplay() -> Bool {
        if displayBounds.isEmpty { status = displayError ?? "The virtual display is not ready yet." }
        return !displayBounds.isEmpty
    }

    private func requireAccessibility() -> Bool {
        if !accessibilityGranted { status = "Grant Accessibility access to move windows and capture the pointer." }
        return accessibilityGranted
    }

    private func requireScreenRecording() -> Bool {
        if !screenRecordingGranted { status = "Grant Screen Recording access, then relaunch Diorama." }
        return screenRecordingGranted
    }
}
