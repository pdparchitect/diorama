import AppKit
import SwiftUI
import DioramaCore

/// Coordinates the virtual display, the capture stream, the pointer bridge and the window actions behind the stage window.
@MainActor
final class DioramaModel: ObservableObject {
    @Published private(set) var status = "Set up Diorama to begin."
    @Published private(set) var captured = false
    @Published private(set) var streaming = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var displayBounds = CGRect.zero
    @Published private(set) var displayPointSize = StageResolution.default.pointSize
    @Published private(set) var lastScreenshot: URL?
    @Published private(set) var displayError: String?
    @Published private(set) var captureError: String?
    @Published private(set) var inputError: String?

    @Published var interactive = true {
        didSet {
            UserDefaults.standard.set(interactive, forKey: Self.interactiveKey)
            pushFence()
            updateReadyStatus()
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
    private var streamTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var streamGeneration = UUID()
    private var nextCaptureAttempt = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private var previousApplication: NSRunningApplication?
    private var started = false

    init() {
        previousApplication = NSWorkspace.shared.frontmostApplication
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

    var mainDisplayBounds: CGRect {
        let main = CGMainDisplayID()
        if main != display.displayID { return CGDisplayBounds(main) }
        return display.otherDisplayBounds().first ?? .zero
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        })
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            MainActor.assumeIsolated {
                guard let app = NSRunningApplication(processIdentifier: pid),
                      app.activationPolicy == .regular,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self?.previousApplication = app
            }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    private func shutdown() {
        started = false
        timer?.invalidate()
        timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        stopCapture()
        bridge.uninstall()
        display.destroy()
    }

    private func stopCapture() {
        streamGeneration = UUID()
        streamTask?.cancel()
        streamTask = nil
        streaming = false
        stageView?.clear()
        pushFence()
        let previousStop = stopTask
        stopTask = Task {
            await previousStop?.value
            await stream.stop()
        }
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
        guard started else { return }
        accessibilityGranted = Permissions.accessibility
        screenRecordingGranted = Permissions.screenRecording
        guard accessibilityGranted, screenRecordingGranted else {
            if display.exists || bridge.isInstalled || streamTask != nil || stream.isRunning {
                stopCapture()
                bridge.uninstall()
                display.destroy()
                displayBounds = .zero
                pushFence()
            }
            status = "Allow Screen Recording and Accessibility to start the stage."
            return
        }
        if !bridge.isInstalled {
            guard bridge.install() else {
                let message = "Diorama could not start pointer control. Check Accessibility access, then reopen Diorama."
                inputError = message
                status = message
                return
            }
            inputError = nil
        }
        if !display.exists, displayError == nil {
            do {
                try display.create(preferred: resolution)
            } catch {
                displayError = error.localizedDescription
                status = error.localizedDescription
            }
        }
        refreshDisplay()
    }

    func retry() {
        displayError = nil
        captureError = nil
        inputError = nil
        nextCaptureAttempt = .distantPast
        poll()
    }

    private func updateReadyStatus() {
        guard streaming else { return }
        status = interactive ? "Interactive: move into the picture to work. Move out to release." : "View only: the pointer stays on your screen."
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
        if let current = display.currentResolution {
            if current != resolution { resolution = current }
        } else if !bounds.isEmpty {
            // macOS brought the display up in a mode Diorama does not offer, or the earlier switch came too soon; try again.
            display.apply(resolution)
        }
        pushFence()
        ensureStream()
    }

    private func pushFence() {
        let geometry: StageGeometry? = if let stageRect, !displayBounds.isEmpty { StageGeometry(stage: stageRect, display: displayBounds) } else { nil }
        bridge.stageWindowNumber = stageWindowNumber
        bridge.update(geometry: geometry, virtualBounds: displayBounds.isEmpty ? nil : displayBounds, physicalBounds: display.otherDisplayBounds(), interactive: interactive && streaming && accessibilityGranted && screenRecordingGranted)
        if captured != bridge.isCaptured { captured = bridge.isCaptured }
    }

    private func ensureStream() {
        guard screenRecordingGranted, accessibilityGranted, !displayBounds.isEmpty, streamTask == nil,
              Date() >= nextCaptureAttempt else { return }
        let pixelSize = display.pixelSize
        guard pixelSize.width > 0, !stream.isRunning || stream.pixelSize != pixelSize else { return }
        let token = UUID()
        streamGeneration = token
        streaming = false
        stageView?.clear()
        pushFence()
        streamTask = Task { [weak self] in
            guard let self else { return }
            defer { if streamGeneration == token { streamTask = nil } }
            await stopTask?.value
            guard started, streamGeneration == token, !Task.isCancelled else { return }
            do {
                try await stream.start(displayID: display.displayID, pixelSize: pixelSize, onFrame: { [weak self] frame in
                    guard let self, self.streamGeneration == token, self.started else { return }
                    self.stageView?.present(frame)
                    if !self.streaming {
                        self.streaming = true
                        self.captureError = nil
                        self.updateReadyStatus()
                        self.pushFence()
                    }
                }, onStop: { [weak self] error in
                    guard let self, self.streamGeneration == token else { return }
                    self.captureFailed(error?.localizedDescription ?? "The capture session ended.")
                })
            } catch is CancellationError {
                // Closing the stage, revoking access, or replacing a stream intentionally cancels startup.
            } catch {
                guard streamGeneration == token else { return }
                captureFailed(error.localizedDescription)
            }
        }
    }

    private func captureFailed(_ message: String) {
        streaming = false
        stageView?.clear()
        captureError = message
        status = "Capture stopped: \(message)"
        nextCaptureAttempt = Date().addingTimeInterval(5)
        pushFence()
    }

    private var targetApplication: NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        let target = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApplication : front
        guard let target, !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return target
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
        guard let application = targetApplication, let placement = WindowMover.frontWindow(of: application) else {
            status = DioramaError.noFrontWindow.localizedDescription
            return
        }
        let name = application.localizedName ?? "The"
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
        guard let application = targetApplication, let placement = WindowMover.frontWindow(of: application) else {
            status = DioramaError.noFrontWindow.localizedDescription
            return
        }
        let name = application.localizedName ?? "The"
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
        if placements.isEmpty {
            status = "No windows in Diorama."
        } else if moved < placements.count {
            status = "Returned \(moved) of \(placements.count) windows. Some applications refused the move."
        } else {
            status = "Returned \(moved) window\(moved == 1 ? "" : "s")."
        }
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
