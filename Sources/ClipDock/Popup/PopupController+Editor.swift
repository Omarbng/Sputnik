import AppKit
import ClipDockCore

/// The editor, in place of the list: ⌘N types in a new saved item, ⌘E edits the selected one.
/// Nothing opens: it's part of the popup, and Esc goes back to the list.
extension PopupController {
    /// `item` nil starts a new saved item (a secret, from the Secrets tab).
    func openEditor(for item: ClipItem?, secret: Bool = false) {
        model.actionMenu = nil
        model.isCollapsed = false
        if let item {
            guard let id = item.id, item.kind == .text || item.kind == .url || item.isSecret else {
                actions.notify("Only text can be edited")
                return
            }
            editorFields.load(name: item.name, text: item.text ?? "", namePlaceholder: "Name (optional)")
            model.editor = EditorState(mode: .edit(id), showsName: item.isPinned, isSecret: item.isSecret)
            focusEditor(on: item.isSecret ? editorFields.secretField : editorFields.textView)
        } else {
            editorFields.load(name: nil, text: "", namePlaceholder: "Name (optional)")
            model.editor = EditorState(mode: .new, showsName: true, isSecret: secret)
            // A secret starts at its value: the name is optional and filled in automatically.
            focusEditor(on: secret ? editorFields.secretField : editorFields.nameField)
        }
    }

    func handleEditor(_ command: EditorCommand) {
        guard let state = model.editor else { return }
        switch command {
        case .cancel:
            closeEditor()
        case .save:
            saveEditor(state)
        case .primary:
            state.canPaste ? pasteEdited() : saveEditor(state)
        case .toggleSecret:
            guard state.canToggleSecret else { return }
            model.editor?.isSecret.toggle()
            model.editor?.message = nil
            if model.editor?.isSecret == true {
                focusEditor(on: editorFields.secretField)
            } else {
                focusEditor(on: editorFields.textView)
            }
        case .selectAll:
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        case .cut:
            NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        case .copy:
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        case .paste:
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        case .undo:
            panel.firstResponder?.undoManager?.undo()
        case .redo:
            panel.firstResponder?.undoManager?.redo()
        }
    }

    func closeEditor() {
        editorFields.clear()
        model.editor = nil
        panel.makeFirstResponder(searchField)
    }

    // MARK: Private

    private func saveEditor(_ state: EditorState) {
        let name = ClipItem.normalizedName(editorFields.name)
        let value = state.isSecret ? editorFields.secret : editorFields.text
        Task {
            do {
                let item: ClipItem
                switch state.mode {
                case .new:
                    item = try await saved.create(name: name, value: value, secret: state.isSecret)
                case .edit(let id):
                    guard let existing = model.item(id: id) else { throw SavedItems.Problem(message: "That item is gone.") }
                    item = try await saved.update(existing, name: name, value: value)
                }
                guard model.editor != nil else { return }  // the popup closed meanwhile
                closeEditor()
                if state.mode == .new {
                    setQuery("")
                    model.scope = item.isSecret ? .secrets : .saved
                }
                model.select(item)
            } catch let problem as SavedItems.Problem {
                model.editor?.message = problem.message
            } catch {
                model.editor?.message = "Couldn't save it."
            }
        }
    }

    /// ⌘↩ while editing: paste the edited text. The original item stays as it was.
    private func pasteEdited() {
        let text = editorFields.text
        guard !text.isEmpty else {
            model.editor?.message = "There's nothing to paste."
            return
        }
        actions.pasteDerived(text, closePopup: { close(.picked) })
    }

    /// SwiftUI adds the editor's fields on its next update, so focus them once they're in the window.
    private func focusEditor(on view: NSView, attempt: Int = 0) {
        if view.window === panel, !view.isHiddenOrHasHiddenAncestor {
            panel.makeFirstResponder(view)
            return
        }
        guard attempt < 20 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in
            self?.focusEditor(on: view, attempt: attempt + 1)
        }
    }
}
