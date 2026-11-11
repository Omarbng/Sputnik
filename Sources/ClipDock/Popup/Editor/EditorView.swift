import ClipDockCore
import SwiftUI

/// The editor, in place of the list: a name (for saved items), the text or the secret, and the
/// keys that save, paste, or cancel. Each key hint is also a button.
struct EditorView: View {
    let state: EditorState
    let fields: EditorFields
    let tokens: Tokens
    let onCommand: (EditorCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(tokens.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                if state.showsName {
                    field(HostedView(view: fields.nameField), height: 30)
                }
                if state.isSecret {
                    field(HostedView(view: fields.secretField), height: 30)
                    note(secretNote)
                    Spacer(minLength: 0)
                } else {
                    field(HostedView(view: fields.textScroll), height: nil)
                }
                if let message = state.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            Rectangle().fill(tokens.border).frame(height: 1)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.mode == .new ? "plus" : "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.mutedForeground)
            Text(state.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tokens.foreground)
            Spacer()
            if state.canToggleSecret {
                Button { onCommand(.toggleSecret) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: state.isSecret ? "lock.fill" : "lock.open")
                        Text("Secret")
                        Keycaps(keys: ["⌘", "L"], color: tokens.mutedForeground)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.isSecret ? tokens.foreground : tokens.mutedForeground)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .frame(height: 26)
                    .background(state.isSecret ? tokens.accent : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(tokens.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Keep it in the Keychain; Touch ID to paste")
            } else if state.isSecret {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.mutedForeground)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: PopupLayout.searchHeight)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("Cancel", keys: ["esc"], command: .cancel)
            Spacer()
            if state.canPaste {
                hint("Paste", keys: ["⌘", "↩"], command: .primary)
            }
            hint("Save", keys: ["⌘", "S"], command: .save)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var secretNote: String {
        let base = "Kept in the macOS Keychain, never in ClipDock's history. Touch ID is needed to paste or copy it."
        return state.mode == .new ? base : "Type a new value, or leave it empty to keep the current one. " + base
    }

    private func field(_ content: some View, height: CGFloat?) -> some View {
        content
            .padding(.horizontal, 8)
            .frame(height: height)
            .frame(maxHeight: height == nil ? .infinity : nil)
            .background(tokens.accent.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.border, lineWidth: 1))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(tokens.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func hint(_ title: String, keys: [String], command: EditorCommand) -> some View {
        Button { onCommand(command) } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                Keycaps(keys: keys, color: tokens.mutedForeground)
            }
            .foregroundStyle(tokens.foreground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Places an AppKit view that something else owns (and focuses).
struct HostedView<V: NSView>: NSViewRepresentable {
    let view: V

    func makeNSView(context: Context) -> V { view }
    func updateNSView(_ nsView: V, context: Context) {}
}
