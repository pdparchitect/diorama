import SwiftUI
import DioramaCore

private enum DioramaSettingsTab: Hashable {
    case general, permissions, updates
}

struct DioramaSettingsView: View {
    let model: DioramaModel
    @State private var selectedTab = DioramaSettingsTab.general

    var body: some View {
        TabView(selection: $selectedTab.animation(.easeInOut(duration: 0.22))) {
            GeneralSettingsView(model: model)
                .settingsContentSize()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(DioramaSettingsTab.general)
            PermissionsSettingsView(model: model)
                .settingsContentSize()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(DioramaSettingsTab.permissions)
            UpdatesSettingsView()
                .settingsContentSize()
                .tabItem { Label("Update", systemImage: "arrow.triangle.2.circlepath") }
                .tag(DioramaSettingsTab.updates)
        }
        .modifier(SettingsWindowResizeAnchor())
        .settingsScrollIndicators(selection: selectedTab)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var model: DioramaModel

    var body: some View {
        Form {
            Section {
                Picker("Resolution", selection: $model.resolution) {
                    ForEach(StageResolution.all) { resolution in
                        Text(resolution.label).tag(resolution)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsSettingsView: View {
    let model: DioramaModel

    var body: some View {
        Form {
            Section {
                permissionRow("Screen Recording", granted: model.screenRecordingGranted) {
                    Permissions.openScreenRecordingSettings()
                }
                .help("Allow Diorama to show and capture the virtual desktop.")
                permissionRow("Accessibility", granted: model.accessibilityGranted) {
                    Permissions.openAccessibilitySettings()
                }
                .help("Allow Diorama to control the pointer and move windows into the stage.")
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Label(granted ? "Allowed" : "Not Allowed",
                  systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .accessibilityLabel("\(title): \(granted ? "Allowed" : "Not Allowed")")
            Button("Open Settings…", action: action)
                .accessibilityLabel("Open \(title) Settings")
        }
    }
}

// Match Noodle's fitted settings panes and keep the tab bar anchored during resizing.
private struct SettingsWindowResizeAnchor: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.windowResizeAnchor(.top)
        } else {
            content
        }
    }
}

private extension View {
    func settingsContentSize() -> some View {
        frame(width: 580)
            .fixedSize(horizontal: false, vertical: true)
    }
}
