import ClipDockCore
@preconcurrency import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    struct Actions {
        var openAccessibilitySettings: () -> Void
        var openPasteSettings: () -> Void
        var downloadLanguages: () -> Void
    }

    @Bindable var model: SettingsModel
    let icons: AppIconCache
    let actions: Actions

    var body: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Open ClipDock", name: .openPopup)
                KeyboardShortcuts.Recorder("Translate selection", name: .translateInPlace)
                KeyboardShortcuts.Recorder("Translate, show only", name: .translateShowOnly)
                note("⌘⇧V takes over \"paste as plain text\" in Chrome and Google Docs.")
            }

            Section("History") {
                Stepper("Keep up to \(model.maxItems) items", value: $model.maxItems, in: 50...5_000, step: 50)
                Stepper("Delete items after \(model.retentionDays) days", value: $model.retentionDays, in: 1...365)
                note("Pinned items are always kept. New limits apply when you close Settings.")
            }

            Section("Paste all (⌘↩)") {
                Picker("Between items", selection: $model.separator) {
                    ForEach(PasteAllSeparator.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            Section("Ignored apps") {
                ForEach(model.ignoredApps, id: \.self) { bundleID in
                    ignoredAppRow(bundleID)
                }
                HStack {
                    Button("Add App…") { model.addIgnoredApp() }
                    Button("Restore Defaults") { model.restoreDefaultIgnoredApps() }
                }
                note("ClipDock never saves what you copy in these apps.")
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let message = model.launchAtLoginMessage { note(message) }
            }

            Section("Permissions") {
                statusRow("Accessibility", detail: "To paste with ⌘V and read selections",
                          ok: model.accessibilityGranted, button: "Open Settings", action: actions.openAccessibilitySettings)
                statusRow("Paste from Other Apps", detail: "To save what you copy",
                          ok: model.pasteAllowed, button: "Open Settings", action: actions.openPasteSettings)
                statusRow("Translation languages", detail: "English and Russian, on this Mac",
                          ok: model.languagesInstalled, button: "Download…", action: actions.downloadLanguages)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 660)
    }

    private func ignoredAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let icon = icons.icon(for: bundleID) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed").frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(SettingsModel.appName(for: bundleID) ?? "Not installed")
                Text(bundleID).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.removeIgnoredApp(bundleID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Stop ignoring this app")
        }
    }

    private func statusRow(_ title: String, detail: String, ok: Bool, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                Text(ok ? detail : "\(detail): not set up").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok { Button(button, action: action) }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
