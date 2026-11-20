import AppKit
import ClipDockCore

/// What the popup's newer actions need: Apple Intelligence, the image tools, the contact
/// actions, and the paste stack.
struct PopupTools {
    let writing: WritingAssistant
    let images: ImageActions
    let contacts: ContactActions
    let pasteStack: PasteStackController
}

/// Quick Look, the writing actions, image and contact actions, translation of images, and the
/// paste stack.
extension PopupController {
    /// The actions menu for an item, with the writing actions when Apple Intelligence is on.
    func availableActions(for item: ClipItem) -> [ClipAction] {
        let writing = AppSettings.isOn(.writingTools) && tools.writing.isAvailable
        return ClipAction.available(for: item, context: .init(writingTools: writing))
    }

    /// Keys while Quick Look is open: Esc, Space, ⇧Space or ⌘Y close it; ↑↓ show the
    /// neighbouring item. Anything else closes it and runs as usual (returns false).
    func handleInPeek(_ command: PopupCommand) -> Bool {
        switch command {
        case .close, .peek, .toggleMark:
            model.peekID = nil
            return true
        case .moveUp, .moveDown:
            model.moveSelection(by: command == .moveUp ? -1 : 1)
            model.peekID = model.selectedItem?.id
            return true
        default:
            model.peekID = nil
            return false
        }
    }

    func togglePeek() {
        guard let item = model.selectedItem, !item.isSecret else {
            if model.selectedItem?.isSecret == true { actions.notify("Secrets stay hidden") }
            return
        }
        model.actionMenu = nil
        model.peekID = model.peekID == item.id ? nil : item.id
    }

    /// ⇧⌘↩: the marked items become a paste stack.
    func startPasteStack() {
        tools.pasteStack.start(model.markedItems, closePopup: { close(.picked) })
    }

    /// ↩ on a row's result: a translation keeps its badge; a rewrite is plain new text.
    func pasteResult(_ text: String) {
        if model.translation?.kind == .rewrite {
            actions.pasteDerived(text, closePopup: { close(.picked) })
        } else {
            actions.pasteTranslation(text, closePopup: { close(.picked) })
        }
    }

    func copyResult(_ text: String) {
        if model.translation?.kind == .rewrite {
            actions.copyDerived(text, closePopup: { close(.picked) })
        } else {
            actions.copyTranslation(text, closePopup: { close(.picked) })
        }
    }

    /// ⌘T: translate the selected row (or the text in an image) and show it under the row.
    func translateSelected() {
        guard let item = model.selectedItem, let id = item.id else { return }
        if let shown = model.translation, shown.itemID == id, shown.kind == .translation { return }
        let isImage = item.kind == .image || item.imageFilePath != nil
        guard isImage || ((item.kind == .text || item.kind == .url) && item.text != nil) else {
            model.translation = RowTranslation(itemID: id, state: .failed("Only text and images can be translated"))
            return
        }
        model.translation = RowTranslation(itemID: id, label: isImage ? "Text in image" : nil, state: .working)
        Task {
            var label: String?
            let state: RowTranslation.State
            do {
                let source = isImage ? try await tools.images.recognizedText(in: item) : (item.text ?? "")
                let direction = translation.direction(for: source)?.label ?? ""
                label = isImage ? "Text in image · \(direction)" : direction
                state = .done(try await translation.translate(source))
            } catch let failure as ImageTools.Failure {
                state = .failed(ImageActions.message(for: failure))
            } catch {
                state = .failed(translation.describe(error))
            }
            guard model.translation?.itemID == id else { return }
            model.translation?.label = label ?? model.translation?.label
            model.translation?.state = state
        }
    }

    /// Proofread, Make Professional, Make Shorter, Summarize: the result appears under the row.
    func rewriteSelected(_ item: ClipItem, style: RewriteStyle) {
        guard let id = item.id, let text = item.text else { return }
        model.translation = RowTranslation(itemID: id, kind: .rewrite, label: style.title, state: .working)
        Task {
            let state: RowTranslation.State
            do {
                state = .done(try await tools.writing.rewrite(text, style: style))
            } catch let failure as WritingAssistant.Unavailable {
                state = .failed(failure.message)
            } catch {
                state = .failed("Apple Intelligence couldn't do it")
            }
            if model.translation?.itemID == id, model.translation?.label == style.title { model.translation?.state = state }
        }
    }

    /// Message on WhatsApp, Call, Write Email, Add to Calendar.
    func runContactAction(_ action: ClipAction, on item: ClipItem) {
        guard let text = item.text else { return }
        let found = ContactDetector.detect(in: text)
        close(.picked)
        switch action {
        case .whatsApp: found.phone.map(tools.contacts.whatsApp)
        case .call: found.phone.map(tools.contacts.call)
        case .email: found.email.map(tools.contacts.email)
        case .addToCalendar: tools.contacts.addToCalendar(text: text, contacts: found)
        default: break
        }
        actions.markUsed(item)
    }

    func runImageAction(_ action: ClipAction, on item: ClipItem) {
        let closePopup = { self.close(.picked) }
        switch action {
        case .copyText: tools.images.copyText(from: item, closePopup: closePopup)
        case .pasteSmaller: tools.images.pasteSmaller(item, closePopup: closePopup)
        case .copyAsJPEG: tools.images.copyAsJPEG(item, closePopup: closePopup)
        case .removeBackground: tools.images.removeBackground(item, closePopup: closePopup)
        default: return
        }
        actions.markUsed(item)
    }
}
