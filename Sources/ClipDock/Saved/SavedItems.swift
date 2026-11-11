import Foundation
import ClipDockCore

/// Creates and edits saved items for the popup's editor. A secret's value goes to the Keychain;
/// its database row holds only the name.
@MainActor
final class SavedItems {
    /// Shown in the editor, so Omar can fix it and try again.
    struct Problem: Error {
        let message: String
    }

    private let database: HistoryDatabase
    private let history: HistoryModel

    init(database: HistoryDatabase, history: HistoryModel) {
        self.database = database
        self.history = history
    }

    /// ⌘N → Save.
    func create(name: String?, value: String, secret: Bool) async throws -> ClipItem {
        let item: ClipItem
        if secret {
            guard let name else { throw Problem(message: "Give the secret a name, so you can find it.") }
            guard !value.isEmpty else { throw Problem(message: "Type or paste the secret first.") }
            let account = UUID().uuidString
            try await keychain { try SecretStore.add(value, account: account) }
            do {
                item = try database.saveSecret(name: name, secretRef: account, now: .now)
            } catch {
                try? await keychain { try SecretStore.delete(account: account) }
                throw Problem(message: "Couldn't save it.")
            }
        } else {
            guard !value.allSatisfy(\.isWhitespace) else { throw Problem(message: "Type something to save.") }
            item = try database.saveText(value, name: name, now: .now)
        }
        history.moveToTop(item)
        Log.storage.notice("saved new id=\(item.id ?? -1, privacy: .public) kind=\(item.kind.rawValue, privacy: .public)")
        return item
    }

    /// ⌘E → Save. For a secret, `value` is a new value, or empty to keep the old one.
    func update(_ item: ClipItem, name: String?, value: String) async throws -> ClipItem {
        guard let id = item.id else { throw Problem(message: "That item is gone.") }
        if item.isSecret {
            guard let name else { throw Problem(message: "A secret needs a name.") }
            if !value.isEmpty, let account = item.secretRef {
                try await keychain { try SecretStore.update(value, account: account) }
            }
            return try store(id: id, text: nil, name: name)
        }
        guard !value.allSatisfy(\.isWhitespace) else { throw Problem(message: "The text can't be empty.") }
        return try store(id: id, text: value, name: item.isPinned ? name : item.name)
    }

    private func store(id: Int64, text: String?, name: String?) throws -> ClipItem {
        do {
            let updated = try database.edit(id: id, text: text, name: name, now: .now)
            history.moveToTop(updated)
            Log.storage.notice("edited id=\(id, privacy: .public)")
            return updated
        } catch HistoryDatabase.EditError.duplicate {
            throw Problem(message: "That text is already in your history.")
        } catch {
            throw Problem(message: "Couldn't save it.")
        }
    }

    private func keychain(_ work: @escaping @Sendable () throws -> Void) async throws {
        do {
            try await Task.detached(operation: work).value
        } catch let failure as SecretStore.Failure {
            Log.storage.error("keychain failed status=\(failure.status, privacy: .public)")
            throw Problem(message: "The Keychain refused it (error \(failure.status)).")
        }
    }
}
