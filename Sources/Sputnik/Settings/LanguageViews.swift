import SputnikCore
import SwiftUI

/// Form rows for the main language, the others, and where the main one translates to. Used in
/// Settings → Translation and in the first-launch setup.
struct TranslationLanguageRows: View {
    @Bindable var languages: LanguagesModel

    var body: some View {
        Picker("I write in", selection: Binding(get: { languages.setup.main }, set: { languages.setMain($0) })) {
            ForEach(TranslationLanguage.catalog) { Text(Self.label($0)).tag($0) }
        }
        ForEach(languages.setup.others) { language in
            HStack {
                Text(language.name)
                if language.nativeName != language.name {
                    Text(language.nativeName).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    languages.remove(language)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove \(language.name)")
            }
        }
        Menu(languages.setup.others.isEmpty ? "Add a Language You Read or Write" : "Add Another Language") {
            ForEach(languages.addable) { language in
                Button(Self.label(language)) { languages.add(language) }
            }
        }
        if !languages.setup.others.isEmpty {
            Picker("Translate \(languages.setup.main.name) into", selection: Binding(
                get: { languages.setup.target },
                set: { languages.setTarget($0) }
            )) {
                ForEach(languages.setup.others) { Text($0.name).tag(Optional($0)) }
            }
        }
    }

    /// "German · Deutsch".
    static func label(_ language: TranslationLanguage) -> String {
        language.nativeName == language.name ? language.name : "\(language.name) · \(language.nativeName)"
    }
}

/// Form rows: which of the chosen languages dictation listens for, with each recogniser's
/// status and download.
struct SpokenLanguageRows: View {
    @Bindable var languages: LanguagesModel

    var body: some View {
        ForEach(languages.setup.all) { language in
            let state = languages.speech[language] ?? .checking
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.name)
                    if let detail = Self.detail(state, spoken: languages.isSpoken(language)) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                switch state {
                case .downloading:
                    ProgressView().controlSize(.small)
                case .notDownloaded where languages.isSpoken(language), .failed where languages.isSpoken(language):
                    Button(state == .failed ? "Try Again" : "Download") { languages.download(language) }
                default:
                    EmptyView()
                }
                Toggle("Dictate in \(language.name)", isOn: Binding(
                    get: { languages.isSpoken(language) },
                    set: { languages.setSpoken(language, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(state == .unavailable || !languages.canAddSpoken(language))
            }
        }
    }

    private static func detail(_ state: LanguagesModel.SpeechState, spoken: Bool) -> String? {
        switch state {
        case .checking: nil
        case .unavailable: "Apple has no dictation for this language yet"
        case .notDownloaded: spoken ? "Needs a download from Apple (a minute or two)" : nil
        case .downloading: "Downloading from Apple…"
        case .ready: spoken ? "Ready" : nil
        case .failed: "The download didn't finish"
        }
    }
}
