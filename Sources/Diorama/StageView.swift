import AppKit
import SwiftUI
import DioramaCore

/// Layer-backed view that shows the captured frames and reports where, on screen, the picture actually is.
final class StageNSView: NSView {
    /// Point size of the virtual display; the picture is aspect-fitted to it inside the view.
    var displayPointSize: CGSize = .zero {
        didSet { if displayPointSize != oldValue { reportGeometry() } }
    }
    /// Called with the picture's rectangle in global coordinates (top-left origin) and the window number, or `nil` when the
    /// picture is not visible on screen.
    var onGeometryChange: ((CGRect?, Int) -> Void)?
    // Retain the buffer as well as the IOSurface until the next frame is installed.
    private var displayedFrame: StageFrame?

    private static let windowNotifications: [Notification.Name] = [
        NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification,
        NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
        NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present(_ frame: StageFrame) {
        displayedFrame = frame
        layer?.contents = frame.surface
    }

    func clear() {
        layer?.contents = nil
        displayedFrame = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let window {
            for name in Self.windowNotifications { NotificationCenter.default.removeObserver(self, name: name, object: window) }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            for name in Self.windowNotifications {
                NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: name, object: window)
            }
        }
        reportGeometry()
    }

    override func layout() {
        super.layout()
        reportGeometry()
    }

    @objc private func environmentChanged(_ notification: Notification) {
        // The window's frame is not final until the notification has been processed, so report on the next turn of the loop.
        if notification.name == NSWindow.willCloseNotification {
            onGeometryChange?(nil, window?.windowNumber ?? 0)
        } else {
            DispatchQueue.main.async { [weak self] in self?.reportGeometry() }
        }
    }

    func reportGeometry() {
        guard let window, window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible),
              displayPointSize.width > 0, let primary = NSScreen.screens.first else {
            onGeometryChange?(nil, window?.windowNumber ?? 0)
            return
        }
        let screenRect = window.convertToScreen(convert(bounds, to: nil))
        let global = CGRect(x: screenRect.minX, y: primary.frame.height - screenRect.maxY, width: screenRect.width, height: screenRect.height)
        let stage = StageGeometry.fit(displayPointSize, in: global)
        onGeometryChange?(stage.isEmpty ? nil : stage, window.windowNumber)
    }
}

struct StageView: NSViewRepresentable {
    @ObservedObject var model: DioramaModel

    func makeNSView(context: Context) -> StageNSView {
        let view = StageNSView(frame: .zero)
        view.onGeometryChange = { [weak model] stage, windowNumber in model?.stageGeometryChanged(stage: stage, windowNumber: windowNumber) }
        model.attach(view)
        return view
    }

    func updateNSView(_ view: StageNSView, context: Context) {
        view.displayPointSize = model.displayPointSize
    }

    static func dismantleNSView(_ view: StageNSView, coordinator: ()) {
        view.onGeometryChange?(nil, view.window?.windowNumber ?? 0)
        view.onGeometryChange = nil
        view.clear()
    }
}
