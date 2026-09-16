import AppKit
import SwiftUI
import DioramaCore

struct StageWindow: View {
    @Bindable var model: DioramaModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                StageView(model: model)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                if !model.streaming { placeholder.preferredColorScheme(.dark) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .frame(minWidth: 640, minHeight: 520)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.interactive) {
                    Label("Interactive", systemImage: model.interactive ? "cursorarrow.motionlines" : "eye")
                }
                .toggleStyle(.button)
                .help("When on, moving the pointer into the picture works inside Diorama. Move out of the picture or push against its edge to leave.")
                Button { model.sendFrontWindow() } label: { Label("Send Front Window", systemImage: "arrow.right.square") }
                    .help("Move the last active application’s front window into Diorama (⌃⌥⌘D)")
                    .disabled(model.displayBounds.isEmpty || !model.accessibilityGranted)
                Button { model.returnAllWindows() } label: { Label("Return All Windows", systemImage: "arrow.uturn.backward.square") }
                    .help("Bring every window back from Diorama to your main display (⌃⌥⌘R)")
                    .disabled(model.displayBounds.isEmpty || !model.accessibilityGranted)
                Button { model.saveScreenshot() } label: { Label("Screenshot", systemImage: "camera") }
                    .help("Capture the whole virtual desktop and open it in Preview (⌃⌥⌘S)")
                    .disabled(!model.streaming)
            }
        }
    }

    private var aspectRatio: CGFloat {
        let size = model.displayPointSize
        return size.height > 0 ? size.width / size.height : 16 / 9
    }

    @ViewBuilder private var placeholder: some View {
        if !model.screenRecordingGranted || !model.accessibilityGranted {
            VStack(spacing: 22) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("A desktop in a box")
                        .font(.title2.weight(.semibold))
                    Text("Allow two permissions to bring your stage to life.")
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 16) {
                    permissionRow("Screen Recording", detail: "Show the virtual desktop in this window.", symbol: "record.circle", granted: model.screenRecordingGranted) {
                        Permissions.requestScreenRecording()
                        Permissions.openScreenRecordingSettings()
                    }
                    Divider()
                    permissionRow("Accessibility", detail: "Control the pointer and move windows into the stage.", symbol: "cursorarrow.motionlines", granted: model.accessibilityGranted) {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
                .padding(20)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                Text("After allowing access in System Settings, reopen Diorama if prompted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 470)
            .padding(28)
        } else if let error = model.displayError ?? model.inputError ?? model.captureError {
            ContentUnavailableView {
                Label("The stage is unavailable", systemImage: "display.trianglebadge.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { model.retry() }
            }
        } else {
            VStack(spacing: 14) {
                ProgressView()
                Text("Preparing your desktop…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(_ title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Allowed")
            } else {
                Button("Allow…", action: action)
                    .accessibilityLabel("Allow \(title)")
            }
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
        .padding(.horizontal, 20)
        .frame(height: 30)
        .background(.bar)
    }
}
