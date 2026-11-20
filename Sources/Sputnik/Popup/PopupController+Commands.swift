import AppKit
import SputnikCore

/// What the list's keys, the actions menu, and the row buttons do.
extension PopupController {
    func perform(_ command: PopupCommand) {
        switch command {
        case .close:
            close(.escape)
        case .moveUp:
            model.moveSelection(by: -1)
        case .moveDown:
            model.moveSelection(by: 1)
        case .pasteSelected:
            if let text = model.selectedTranslation {
                pasteResult(text)
            } else if let item = model.selectedItem {
                paste(item)
            }
        case .pastePlain:
            // Works on any text, formatted or not; images and secrets get a hint instead.
            if let item = model.selectedItem { actions.pastePlain(item, closePopup: { close(.picked) }) }
        case .pasteNumber(let number):
            if let item = model.item(at: number - 1) { paste(item) }
        case .copySelected:
            if let text = model.selectedTranslation {
                copyResult(text)
            } else if let item = model.selectedItem {
                actions.copy(item, closePopup: { close(.picked) })
            }
        case .translateSelected:
            translateSelected()
        case .toggleMark:
            guard let item = model.selectedItem, let id = item.id else { break }
            if item.isSecret {
                actions.notify("Secrets paste one at a time")
            } else {
                model.marks.toggle(id)
            }
        case .pasteMarked:
            if model.marks.isEmpty {
                perform(.pasteSelected)
            } else {
                actions.pasteAll(model.markedItems, closePopup: { close(.picked) })
            }
        case .togglePin:
            if let item = model.selectedItem { run(.togglePin, on: item) }
        case .openSettings:
            close(.other)
            onOpenSettings?()
        case .deleteSelected:
            if let item = model.selectedItem { requestDelete(item) }
        case .showActions:
            if let item = model.selectedItem { showActions(for: item) }
        case .openSelected:
            if let item = model.selectedItem { run(.open, on: item) }
        case .editSelected:
            if let item = model.selectedItem { run(.edit, on: item) }
        case .newSaved:
            openEditor(for: nil, secret: model.scope == .secrets)
        case .switchScope:
            model.scope = model.scope.next
        case .previousScope:
            model.scope = model.scope.previous
        case .saveAsSecret:
            if let item = model.selectedItem { run(.saveAsSecret, on: item) }
        case .peek:
            togglePeek()
        case .pasteOneByOne:
            startPasteStack()
        case .selectAllText:
            searchField.currentEditor()?.selectAll(nil)
        case .cutText:
            searchField.currentEditor()?.cut(nil)
        case .pasteText:
            // In the Secrets tab, ⌘V with an empty search saves what you copied as a secret.
            if model.scope == .secrets, model.query.isEmpty {
                saveCopiedAsSecret()
            } else {
                searchField.currentEditor()?.paste(nil)
            }
        }
    }

    /// Keys while the actions menu is open: ↑↓ move, ↩ runs, Esc closes the menu (not the
    /// popup). Any other shortcut closes the menu and runs as usual.
    func handleInMenu(_ command: PopupCommand) -> Bool {
        guard let menu = model.actionMenu, let item = model.actionMenuItem else {
            model.actionMenu = nil
            return handle(command)
        }
        switch command {
        case .close:
            model.actionMenu = nil
        case .moveUp:
            model.moveActionHighlight(by: -1)
        case .moveDown:
            model.moveActionHighlight(by: 1)
        case .pasteSelected:
            run(menu.actions[menu.highlighted], on: item)
        case .toggleMark, .switchScope, .previousScope:
            break
        default:
            model.actionMenu = nil
            return handle(command)
        }
        return true
    }

    func showActions(for item: ClipItem) {
        guard let id = item.id else { return }
        model.select(item)
        model.pendingDeleteID = nil
        model.isCollapsed = false
        model.peekID = nil
        model.actionMenu = ActionMenuState(itemID: id, actions: availableActions(for: item))
    }

    /// Runs an action on an item, from the menu, a shortcut, or a button.
    func run(_ action: ClipAction, on item: ClipItem) {
        model.actionMenu = nil
        guard availableActions(for: item).contains(action) else {
            actions.notify(Self.unavailableMessage(action, item))
            return
        }
        model.select(item)
        switch action {
        case .paste:
            paste(item)
        case .pastePlain:
            actions.pastePlain(item, closePopup: { close(.picked) })
        case .copy:
            actions.copy(item, closePopup: { close(.picked) })
        case .edit:
            openEditor(for: item)
        case .translate:
            translateSelected()
        case .open:
            actions.open(item, closePopup: { close(.picked) })
        case .togglePin:
            actions.togglePin(item)
            model.clampSelection()
        case .saveAsSecret:
            if let text = item.text { keepAsSecret(text, name: item.name) }
        case .uppercase, .lowercase, .tidy:
            pasteCleaned(item, action)
        case .delete:
            requestDelete(item)
        case .peek:
            model.peekID = item.id
        case .proofread, .professional, .shorter, .summarize:
            if let style = action.rewriteStyle { rewriteSelected(item, style: style) }
        case .whatsApp, .call, .email, .addToCalendar:
            runContactAction(action, on: item)
        case .copyText, .pasteSmaller, .copyAsJPEG, .removeBackground:
            runImageAction(action, on: item)
        }
    }

    /// Plain history items go at once. Saved items, which you can't copy again, ask first:
    /// the row shows "Delete?" until a second ⌘⌫ or click.
    func requestDelete(_ item: ClipItem) {
        guard let id = item.id else { return }
        model.actionMenu = nil
        if item.isPinned, model.pendingDeleteID != id {
            model.select(item)
            model.pendingDeleteID = id
            return
        }
        model.pendingDeleteID = nil
        actions.delete(item)
        model.clampSelection()
    }

    func paste(_ item: ClipItem) {
        actions.paste(item, closePopup: { close(.picked) })
    }

    /// ⌘V in the Secrets tab: saves the copied text as a secret, named automatically.
    func saveCopiedAsSecret() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.allSatisfy(\.isWhitespace)
        else {
            actions.notify("Copy the key first, then press ⌘V here")
            return
        }
        keepAsSecret(text, name: nil)
    }

    /// One step, no typing: the text goes to the Keychain, any plain copy leaves history, and
    /// the Secrets tab opens with the new secret selected. ⌘E renames it.
    private func keepAsSecret(_ text: String, name: String?) {
        model.actionMenu = nil
        Task {
            do {
                let secret = try await saved.saveSecret(text, name: name)
                setQuery("")
                model.scope = .secrets
                model.select(secret)
            } catch let problem as SavedItems.Problem {
                actions.notify(problem.message)
            } catch {
                actions.notify("Couldn't save it")
            }
        }
    }

    private func pasteCleaned(_ item: ClipItem, _ action: ClipAction) {
        guard let text = item.text else { return }
        let cleaned = switch action {
        case .uppercase: TextCleanup.uppercased(text)
        case .lowercase: TextCleanup.lowercased(text)
        default: TextCleanup.tidied(text)
        }
        actions.pasteDerived(cleaned, closePopup: { close(.picked) })
    }

    private static func unavailableMessage(_ action: ClipAction, _ item: ClipItem) -> String {
        switch action {
        case .open: "Only links and files open"
        case .edit: "Only text can be edited"
        case .pastePlain: item.kind == .image ? "Images have no text" : "That item has no formatting"
        case .togglePin: "Secrets are always saved"
        case .proofread, .professional, .shorter, .summarize: "Turn on Apple Intelligence and the writing actions in Settings"
        case .saveAsSecret: item.isSecret ? "It's already a secret" : "Only text can be a secret"
        default: "Not for this item"
        }
    }
}
