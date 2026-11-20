import ClipDockCore
@preconcurrency import KeyboardShortcuts
import SwiftUI

/// Four tabs: General (shortcuts, launch, permissions), Clipboard, Translation, Dictation.
/// Every feature added on 2026-11-19 has its own switch, on by default.
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
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            clipboard.tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            translation.tabItem { Label("Translation", systemImage: "character.bubble") }
            dictation.tabItem { Label("Dictation", systemImage: "mic") }
        }
        .frame(width: 520, height: 640)
    }

    // MARK: Tabs

    private var general: some View {
        Form {
            Section("Shortcuts") {
                tapPicker("Open clipboard history", selection: $model.popupTap)
                tapPicker("Translate selected text", selection: $model.translateTap)
                tapPicker("Proofread selected text", selection: $model.proofreadTap)
                note("Tap the key twice, quickly, on its own. In the translation card, ↩ replaces the text, ⌘C copies it, and Esc closes it. Proofread fixes the selection in place with Apple Intelligence (⌘Z undoes it). Hold fn to dictate (see Dictation). Menu bar → Shortcuts… lists every key.")
            }
            Section("Key combinations (optional)") {
                KeyboardShortcuts.Recorder("Open clipboard history", name: .openPopup)
                KeyboardShortcuts.Recorder("Translate selected text", name: .translate)
                note("Use these if you'd rather press a combination, such as ⌘⇧V.")
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let message = model.launchAtLoginMessage { note(message) }
            }
            Section("Permissions") {
                statusRow("Accessibility", detail: "To paste with ⌘V, read selections, and watch fn",
                          ok: model.accessibilityGranted, button: "Open Settings", action: actions.openAccessibilitySettings)
                statusRow("Paste from Other Apps", detail: "To save what you copy",
                          ok: model.pasteAllowed, button: "Open Settings", action: actions.openPasteSettings)
                statusRow("Microphone", detail: "For dictation, only while you hold fn",
                          ok: model.microphone == .authorized, button: "Allow…", action: model.allowMicrophone)
            }
        }
        .formStyle(.grouped)
    }

    private var clipboard: some View {
        Form {
            Section("Automatic") {
                switchRow(.cleanLinks, "Clean tracking from copied links",
                          "Removes utm_…, fbclid, gclid and similar from links you copy, in history and on the clipboard.")
                switchRow(.expireSensitive, "Forget sensitive copies after 10 minutes",
                          "API keys, card numbers, IBANs and one-time codes leave history (⏱ on the row). ⌘P keeps one.")
            }
            Section("Actions menu (⌘K)") {
                switchRow(.writingTools, "Writing actions with Apple Intelligence",
                          "Proofread, Make Professional, Make Shorter and Summarize, on this Mac. Best in English; Russian is weaker.")
                if let problem = model.writingProblem, model.isOn(.writingTools) { warning(problem) }
                note("Also in ⌘K: Copy Text in Image, Paste Smaller Image, Copy as JPEG, Remove Background, and Message on WhatsApp, Call, Email or Add to Calendar when the text has a number, address or date. ⇧Space or ⌘Y shows an item in full; ⇧⌘↩ pastes marked items one by one.")
            }
            Section("History") {
                Stepper("Keep up to \(model.maxItems) items", value: $model.maxItems, in: 50...5_000, step: 50)
                Stepper("Delete items after \(model.retentionDays) days", value: $model.retentionDays, in: 1...365)
                note("Saved items are always kept. New limits apply when you close Settings.")
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
        }
        .formStyle(.grouped)
    }

    private var translation: some View {
        Form {
            Section("Translation") {
                Picker("Translate English into", selection: $model.englishTarget) {
                    ForEach(TranslationLanguage.englishTargets, id: \.self) { Text($0.name).tag($0) }
                }
                note("French and Russian always translate into English.")
                switchRow(.replyInTheirLanguage, "Reply in their language",
                          "After you translate a French or Russian message, your English goes back into that language for the next hour.")
                switchRow(.translateClipboard, "Translate the clipboard when nothing is selected",
                          "Double-tap ⌃ with nothing selected translates what you just copied, such as a WhatsApp message (right-click → Copy, then ⌃⌃).")
            }
            Section("Languages") {
                statusRow("Translation languages", detail: "English, Russian and French, on this Mac",
                          ok: model.languagesInstalled, button: "Download…", action: actions.downloadLanguages)
            }
        }
        .formStyle(.grouped)
    }

    private var dictation: some View {
        Form {
            Section("Dictation") {
                switchRow(.dictation, "Hold fn to dictate",
                          "Hold fn, speak, let go: the text is typed where you are. Double-tap fn for hands-free (fn again to finish, Esc to cancel). Tap ⇧ while talking to type it translated.")
                switchRow(.rightOptionTalk, "Hold right ⌥ to dictate too",
                          "Works like fn, for keyboards without it or if it's easier to reach. A quick tap (⌥⌥) and ⌥ with a letter still work as usual.")
                Picker("Language", selection: $model.dictationLanguage) {
                    ForEach(AppSettings.DictationLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                switchRow(.dictationRules, "Remove filler words, handle “new line”",
                          "Drops um, uh, эм; “new line” / “новая строка” and “new paragraph” / “новый абзац” become line breaks.")
                switchRow(.dictationPolish, "Polish with Apple Intelligence",
                          "Fixes punctuation, false starts and self-corrections (“at three, actually four” → “at four”), in English and Russian. On this Mac; adds about half a second. A result that changes language or length too much is thrown away.")
                if let problem = model.writingProblem, model.isOn(.dictationPolish) { warning(problem) }
                switchRow(.sayLanguage, "Say the language first",
                          "When translating (fn + ⇧), start with “in French”, “in Russian” or “in English” (or “по-французски”, “на английском”) to pick the language just this once. Those words aren't typed.")
                switchRow(.voiceCommands, "Voice commands",
                          "Select text, hold fn, tap ⌃ and say “translate to Russian”, “make it shorter”, “proofread” or anything else. Say “insert <name>” to paste a saved item.")
            }
            Section("Personal dictionary") {
                TextEditor(text: $model.vocabulary)
                    .font(.system(size: 12))
                    .frame(height: 64)
                note("Names and words dictation should know, one per line (for example, client or product names).")
            }
            Section("Status") {
                statusRow("Microphone", detail: "Asked the first time you hold fn",
                          ok: model.microphone == .authorized, button: "Allow…", action: model.allowMicrophone)
                statusRow("English speech", detail: "Apple's on-device recogniser",
                          ok: model.englishSpeechInstalled, button: "", action: {})
                HStack {
                    statusRow("Russian speech", detail: model.downloadMessage ?? "Apple's on-device recogniser",
                              ok: model.russianSpeechInstalled, button: model.downloadingRussian ? "" : "Download…",
                              action: model.downloadRussianSpeech)
                    if model.downloadingRussian { ProgressView().controlSize(.small) }
                }
                if let conflict = model.fnKeyConflict {
                    HStack {
                        warning("\(conflict). In Keyboard settings, set “Press 🌐 key to” to “Do Nothing”.")
                        Spacer()
                        Button("Keyboard Settings") { model.openKeyboardSettings() }
                    }
                }
                if model.wisprFlowRunning {
                    warning("Wispr Flow is running and also uses fn. Change its shortcut, or quit it.")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Rows

    private func switchRow(_ setting: AppSettings.Switch, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: Binding(get: { model.isOn(setting) }, set: { model.set(setting, $0) }))
            note(detail)
        }
    }

    private func tapPicker(_ title: String, selection: Binding<TapModifier?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(TapModifier.allCases, id: \.self) { modifier in
                Text("Tap \(modifier.symbol) \(modifier.name) twice").tag(Optional(modifier))
            }
            Divider()
            Text("Off").tag(TapModifier?.none)
        }
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
            if !ok, !button.isEmpty { Button(button, action: action) }
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
