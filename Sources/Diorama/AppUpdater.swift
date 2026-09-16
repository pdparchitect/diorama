import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyDownloads = false
    @Published private(set) var allowsAutomaticUpdates = false
    static var updatesEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "DioramaUpdatesEnabled") as? Bool == true
    }

    private var started = false
    private lazy var controller = SPUStandardUpdaterController(
        // Sparkle relaunches through the normal app shutdown, releasing the stage.
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )

    func start() {
        guard !started, Self.updatesEnabled else { return }
        started = true
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyDownloads)
        updater.publisher(for: \.allowsAutomaticUpdates).assign(to: &$allowsAutomaticUpdates)
        controller.startUpdater()
    }

    func checkForUpdates() {
        if started { controller.checkForUpdates(nil) }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        if started { controller.updater.automaticallyChecksForUpdates = enabled }
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        if started { controller.updater.automaticallyDownloadsUpdates = enabled }
    }

}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

struct UpdatesSettingsView: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                }
                CheckForUpdatesButton()
            }
            Section {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecks }, set: updater.setAutomaticChecks
                ))
                Toggle("Automatically download and install updates", isOn: Binding(
                    get: { updater.automaticallyDownloads }, set: updater.setAutomaticDownloads
                ))
                .disabled(!updater.allowsAutomaticUpdates)
            }
            .disabled(!AppUpdater.updatesEnabled)
            .help(AppUpdater.updatesEnabled
                  ? "Installing an update restarts Diorama and returns the stage’s windows to your desktop."
                  : "Updates are available in distributed releases.")
        }
        .formStyle(.grouped)
    }
}
