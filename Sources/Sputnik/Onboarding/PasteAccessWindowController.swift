import AppKit

/// Shows the paste-permission card. It closes itself once access is allowed.
@MainActor
final class PasteAccessWindowController {
    private let card = CardWindow()

    func show(access: NSPasteboard.AccessBehavior) {
        guard access != .alwaysAllow else { return }
        card.show(view(for: access))
    }

    /// Re-renders for a new permission state. Does nothing if the card isn't showing.
    func update(access: NSPasteboard.AccessBehavior) {
        guard card.isShowing else { return }
        if access == .alwaysAllow {
            card.close()
        } else {
            card.setContent(view(for: access))
        }
    }

    private func view(for access: NSPasteboard.AccessBehavior) -> PasteAccessCardView {
        PasteAccessCardView(
            access: access,
            onContinue: { PasteboardAccess.requestListing() },
            onOpenSettings: { PasteboardAccess.openSettings() },
            onDismiss: { [card] in card.close() }
        )
    }
}
