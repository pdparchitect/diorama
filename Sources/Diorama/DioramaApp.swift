import AppKit
import SwiftUI
import DioramaCore

@main
struct DioramaApp: App {
    @NSApplicationDelegateAdaptor(DioramaApplicationDelegate.self) private var appDelegate
    @State private var model = DioramaModel()

    var body: some Scene {
        Window("Diorama", id: "stage") {
            StageWindow(model: model)
                .preferredColorScheme(.dark)
                .onAppear { model.start() }
                .onDisappear { NSApp.terminate(nil) }
        }
        .defaultSize(width: 1120, height: 690)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            StageCommands(model: model)
            CommandGroup(after: .appSettings) { CheckForUpdatesButton() }
            CommandGroup(replacing: .help) {
                Button("Diorama Help") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/pdparchitect/diorama")!)
                }
            }
        }

        Settings {
            DioramaSettingsView(model: model)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }
}

struct StageCommands: Commands {
    @Bindable var model: DioramaModel

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
            Button("Retry Stage") { model.retry() }
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

final class DioramaApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppUpdater.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
