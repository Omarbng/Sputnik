import Foundation
import Testing
@testable import ClipDockCore

@Suite("Saved items")
struct SavedItemsTests {
    let history: TemporaryHistory
    var db: HistoryDatabase { history.database }
    let policy = RetentionPolicy(maxUnpinned: 500, maxAgeDays: 30)

    init() throws { history = try TemporaryHistory() }

    @Test("Typed-in text is saved (pinned) with its name, and never expires")
    func saveText() throws {
        let item = try db.saveText("12 Main Street", name: "Office address", now: daysAgo(90))
        #expect(item.isPinned)
        #expect(item.name == "Office address")
        #expect(item.kind == .text)
        #expect(item.sourceBundleID == nil)
        try db.applyRetention(policy, now: referenceNow)
        #expect(try db.allItems().map(\.id) == [item.id])
    }

    @Test("Saving text that's already in history saves that item instead of a copy")
    func saveTextDedupes() throws {
        let link = CapturedClip(payload: .url("https://example.com"), sourceBundleID: nil, sourceAppName: nil, capturedAt: daysAgo(1))
        let copied = try db.ingest(link, retention: policy)
        let saved = try db.saveText("https://example.com", name: "Example", now: referenceNow)
        #expect(saved.id == copied.item.id)
        #expect(saved.isPinned)
        #expect(saved.kind == .url)
        #expect(saved.name == "Example")
        #expect(try db.allItems().count == 1)
    }

    @Test("A secret's row holds its name and Keychain reference, never a value")
    func saveSecret() throws {
        let secret = try db.saveSecret(name: "Bank PIN", secretRef: "ref-1", now: referenceNow)
        let stored = try #require(try db.allItems().first)
        #expect(stored.id == secret.id)
        #expect(stored.kind == .secret)
        #expect(stored.text == nil)
        #expect(stored.secretRef == "ref-1")
        #expect(stored.isPinned)
        #expect(stored.byteSize == 0)
    }

    @Test("Secrets survive Clear history")
    func secretsSurviveClear() throws {
        let secret = try db.saveSecret(name: "Key", secretRef: "ref-2", now: referenceNow)
        _ = try db.ingest(textClip("throwaway"), retention: policy)
        try db.clearUnpinned()
        #expect(try db.allItems().map(\.id) == [secret.id])
    }

    @Test("Editing text updates the item, drops its RTF, and moves it to the top")
    func editText() throws {
        let rich = CapturedClip(
            payload: .text("Hello", rtf: Data("{\\rtf1 Hello}".utf8)),
            sourceBundleID: "com.apple.TextEdit", sourceAppName: "TextEdit", capturedAt: daysAgo(1)
        )
        let original = try db.ingest(rich, retention: policy).item
        _ = try db.ingest(textClip("newer", at: daysAgo(0.5)), retention: policy)
        #expect(try history.blobFiles().count == 1)

        let edited = try db.edit(id: original.id!, text: "Hello, world", name: nil, now: referenceNow)
        #expect(edited.text == "Hello, world")
        #expect(edited.rtfBlob == nil)
        #expect(edited.contentHash == textClip("Hello, world").contentHash)
        #expect(try db.allItems().first?.id == original.id)
        #expect(try history.blobFiles().isEmpty)
    }

    @Test("Editing into text another item already has is refused")
    func editDuplicate() throws {
        let first = try db.ingest(textClip("one"), retention: policy).item
        _ = try db.ingest(textClip("two"), retention: policy)
        #expect(throws: HistoryDatabase.EditError.duplicate) {
            try db.edit(id: first.id!, text: "two", name: nil, now: referenceNow)
        }
    }

    @Test("Renaming a secret keeps it a secret, with no text")
    func renameSecret() throws {
        let secret = try db.saveSecret(name: "Old", secretRef: "ref-3", now: daysAgo(1))
        let renamed = try db.edit(id: secret.id!, text: "ignored for secrets", name: "New", now: referenceNow)
        #expect(renamed.name == "New")
        #expect(renamed.kind == .secret)
        #expect(renamed.text == nil)
        #expect(renamed.contentHash == "secret:ref-3")
    }

    @Test("Names are trimmed, and a blank name means none")
    func names() {
        #expect(ClipItem.normalizedName("  OpenAI key \n") == "OpenAI key")
        #expect(ClipItem.normalizedName("   ") == nil)
        #expect(ClipItem.normalizedName(nil) == nil)
    }

    @Test("Saving a copied key as a secret removes its plain copies from history, and their blobs")
    func saveSecretRemovesCopies() throws {
        let rich = CapturedClip(
            payload: .text("sk-proj-abc\n", rtf: Data("{\\rtf1 x}".utf8)),
            sourceBundleID: nil, sourceAppName: nil, capturedAt: daysAgo(1)
        )
        let copy = try db.ingest(rich, retention: policy).item
        let trimmedCopy = try db.ingest(textClip("sk-proj-abc"), retention: policy).item
        let other = try db.ingest(textClip("keep me"), retention: policy).item
        let (secret, removed) = try db.saveSecret(
            name: "OpenAI key", secretRef: "ref-5", now: referenceNow,
            removingPlainCopies: [copy.contentHash, trimmedCopy.contentHash]
        )
        #expect(Set(removed) == [copy.id!, trimmedCopy.id!])
        #expect(Set(try db.allItems().map(\.id)) == [secret.id, other.id])
        #expect(try history.blobFiles().isEmpty)
    }

    @Test("Paste all leaves secrets out")
    func pasteAllSkipsSecrets() throws {
        let text = try db.ingest(textClip("visible"), retention: policy).item
        let secret = try db.saveSecret(name: "Hidden", secretRef: "ref-4", now: referenceNow)
        let (joined, skipped) = PasteAll.join([text, secret], separator: .newline)
        #expect(joined == "visible")
        #expect(skipped == 1)
    }
}

@Suite("Actions menu")
struct ClipActionTests {
    func item(_ kind: ClipKind, rtf: String? = nil, pinned: Bool = false) -> ClipItem {
        ClipItem(
            id: 1, kind: kind, text: kind == .secret ? nil : "x", rtfBlob: rtf, contentHash: "h",
            byteSize: 1, createdAt: referenceNow, lastUsedAt: referenceNow, isPinned: pinned
        )
    }

    @Test("Text gets every action; Paste as Plain Text only when it has formatting")
    func text() {
        #expect(ClipAction.available(for: item(.text)) == [
            .paste, .copy, .edit, .translate, .togglePin, .saveAsSecret, .uppercase, .lowercase, .tidy, .delete,
        ])
        #expect(ClipAction.available(for: item(.text, rtf: "a.rtf")).prefix(2) == [.paste, .pastePlain])
    }

    @Test("Links open; files show in Finder and paste as a path")
    func linksAndFiles() {
        #expect(ClipAction.available(for: item(.url)).contains(.open))
        #expect(!ClipAction.available(for: item(.url)).contains(.translate))
        let file = item(.file)
        #expect(ClipAction.available(for: file).contains(.pastePlain))
        #expect(!ClipAction.available(for: file).contains(.saveAsSecret))
        #expect(ClipAction.available(for: item(.url)).contains(.saveAsSecret))
        #expect(ClipAction.open.title(for: file) == "Show in Finder")
        #expect(ClipAction.pastePlain.title(for: file) == "Paste as Path")
    }

    @Test("Secrets offer only paste, copy, edit, and delete")
    func secrets() {
        #expect(ClipAction.available(for: item(.secret)) == [.paste, .copy, .edit, .delete])
    }

    @Test("Save or unsave depends on the item")
    func pinTitle() {
        #expect(ClipAction.togglePin.title(for: item(.text)) == "Add to Saved")
        #expect(ClipAction.togglePin.title(for: item(.text, pinned: true)) == "Remove from Saved")
    }
}

@Suite("Secret names")
struct SecretNamerTests {
    @Test("Known key prefixes name the kind of key")
    func prefixes() {
        #expect(SecretNamer.name(for: "sk-proj-AbC123", existing: []) == "OpenAI key")
        #expect(SecretNamer.name(for: "sk-ant-api03-xyz", existing: []) == "Anthropic key")
        #expect(SecretNamer.name(for: "  ghp_abcdef \n", existing: []) == "GitHub token")
        #expect(SecretNamer.name(for: "AKIAIOSFODNN7EXAMPLE", existing: []) == "AWS key")
        #expect(SecretNamer.name(for: "hunter2", existing: []) == "Secret")
    }

    @Test("An environment line is named after its variable")
    func variables() {
        #expect(SecretNamer.name(for: "OPENAI_API_KEY=sk-proj-1", existing: []) == "OPENAI_API_KEY")
        #expect(SecretNamer.name(for: "export STRIPE_KEY = sk_live_1", existing: []) == "STRIPE_KEY")
        #expect(SecretNamer.name(for: "A=1\nB=2", existing: []) == "Secret")
        #expect(SecretNamer.name(for: "EMPTY=", existing: []) == "Secret")
    }

    @Test("Prose that starts like a key isn't named as one")
    func prose() {
        #expect(SecretNamer.name(for: "ASIA trip plans", existing: []) == "Secret")
    }

    @Test("A name in use gets the next number")
    func numbering() {
        #expect(SecretNamer.name(for: "sk-1", existing: ["OpenAI key"]) == "OpenAI key 2")
        #expect(SecretNamer.name(for: "x", existing: ["Secret", "Secret 2"]) == "Secret 3")
    }
}

@Suite("Clean up text")
struct TextCleanupTests {
    @Test("UPPERCASE and lowercase, including Cyrillic")
    func cases() {
        #expect(TextCleanup.uppercased("Hello, мир") == "HELLO, МИР")
        #expect(TextCleanup.lowercased("Hello, МИР") == "hello, мир")
    }

    @Test("Broken lines join and repeated spaces squeeze, keeping paragraphs")
    func tidy() {
        let messy = "  This is   a line\nbroken in\r\nthe middle.\n\n\n  Second\tparagraph.  \n"
        #expect(TextCleanup.tidied(messy) == "This is a line broken in the middle.\n\nSecond paragraph.")
    }

    @Test("Blank text stays blank")
    func blank() {
        #expect(TextCleanup.tidied(" \n\n \t") == "")
    }
}
