import AppKit
import SwiftUI
import DioramaCore

@main
struct DioramaApp: App {
    @StateObject private var model = DioramaModel()

    var body: some Scene {
        Window("Diorama", id: "stage") {
            StageWindow(model: model)
                .onAppear { model.start() }
        }
        .defaultSize(width: 1120, height: 690)
        .commands { StageCommands(model: model) }
    }
}

struct StageCommands: Commands {
    @ObservedObject var model: DioramaModel

    var body: some Commands {
        CommandMenu("Stage") {
            Toggle(Hotkey.toggleInteractive.title, isOn: $model.interactive)
                .keyboardShortcut(shortcut(for: .toggleInteractive), modifiers: Self.modifiers)
            Button("Release Pointer") { model.releasePointer() }
                .disabled(!model.captured)
            Divider()
            Button(Hotkey.sendFrontWindow.title) { model.sendFrontWindow() }
                .keyboardShortcut(shortcut(for: .sendFrontWindow), modifiers: Self.modifiers)
            Button(Hotkey.returnFrontWindow.title) { model.returnFrontWindow() }
                .keyboardShortcut(shortcut(for: .returnFrontWindow), modifiers: Self.modifiers)
            Button(Hotkey.returnAllWindows.title) { model.returnAllWindows() }
                .keyboardShortcut(shortcut(for: .returnAllWindows), modifiers: Self.modifiers)
            Divider()
            Picker("Resolution", selection: $model.resolution) {
                ForEach(StageResolution.all) { resolution in
                    Text(resolution.label).tag(resolution)
                }
            }
            Divider()
            Button(Hotkey.saveScreenshot.title) { model.saveScreenshot() }
                .keyboardShortcut(shortcut(for: .saveScreenshot), modifiers: Self.modifiers)
            Button("Copy Screenshot") { model.copyScreenshot() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Show Screenshots in Finder") { model.showScreenshots() }
        }
    }

    private static let modifiers: EventModifiers = [.control, .option, .command]

    private func shortcut(for hotkey: Hotkey) -> KeyEquivalent {
        KeyEquivalent(Character(hotkey.letter.lowercased()))
    }
}

struct StageWindow: View {
    @ObservedObject var model: DioramaModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                StageView(model: model)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                if !model.streaming { placeholder }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .frame(minWidth: 640, minHeight: 400)
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.interactive) {
                    Label("Interactive", systemImage: model.interactive ? "cursorarrow.motionlines" : "eye")
                }
                .toggleStyle(.button)
                .help("When on, moving the pointer into the picture works inside Diorama. Move out of the picture or push against its edge to leave.")
                Button { model.sendFrontWindow() } label: { Label("Send Front Window", systemImage: "arrow.right.square") }
                    .help("Move the front window of the active application into Diorama (⌃⌥⌘D)")
                Button { model.returnAllWindows() } label: { Label("Return All Windows", systemImage: "arrow.uturn.backward.square") }
                    .help("Bring every window back from Diorama to your main display (⌃⌥⌘R)")
                Button { model.saveScreenshot() } label: { Label("Screenshot", systemImage: "camera") }
                    .help("Save a full-resolution screenshot of the whole virtual desktop (⌃⌥⌘S)")
            }
        }
    }

    private var aspectRatio: CGFloat {
        let size = model.displayPointSize
        return size.height > 0 ? size.width / size.height : 16 / 9
    }

    @ViewBuilder private var placeholder: some View {
        if let error = model.displayError {
            ContentUnavailableView("The virtual display could not be created", systemImage: "display.trianglebadge.exclamationmark", description: Text(error))
        } else if !model.screenRecordingGranted {
            ContentUnavailableView {
                Label("Screen Recording access needed", systemImage: "record.circle")
            } description: {
                Text("Diorama shows the virtual display by capturing it. Allow Diorama under Screen & System Audio Recording, then relaunch the app.")
            } actions: {
                Button("Open Privacy Settings") { Permissions.openScreenRecordingSettings() }
            }
        } else {
            ContentUnavailableView("Preparing the virtual display", systemImage: "display", description: Text("The stage appears as soon as macOS brings the display online."))
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.captured ? Color.green : (model.streaming ? Color.secondary.opacity(0.5) : Color.orange))
                .frame(width: 8, height: 8)
                .help(model.captured ? "The pointer is inside Diorama" : "The pointer is on your screen")
            Text(model.status)
                .lineLimit(1)
                .truncationMode(.tail)
            if !model.accessibilityGranted {
                Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
                    .buttonStyle(.link)
                    .help("Accessibility access lets Diorama fence the pointer and move windows between displays.")
            }
            Spacer()
            Text(model.displayBounds.isEmpty ? "No display" : "\(Int(model.displayBounds.width)) × \(Int(model.displayBounds.height)) points")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
