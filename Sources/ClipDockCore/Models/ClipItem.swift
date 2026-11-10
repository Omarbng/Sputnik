import Foundation
import GRDB

/// A stored history item. Large payloads (RTF, PNG) live in `blobs/`, referenced by file name.
public struct ClipItem: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var kind: ClipKind
    public var text: String?
    public var rtfBlob: String?
    public var imageBlob: String?
    public var contentHash: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var byteSize: Int
    public var createdAt: Date
    /// Ordering key. Re-copying or pasting an item bumps it to the top.
    public var lastUsedAt: Date
    public var isPinned: Bool

    public init(
        id: Int64? = nil,
        kind: ClipKind,
        text: String?,
        rtfBlob: String? = nil,
        imageBlob: String? = nil,
        contentHash: String,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        byteSize: Int,
        createdAt: Date,
        lastUsedAt: Date,
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.rtfBlob = rtfBlob
        self.imageBlob = imageBlob
        self.contentHash = contentHash
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isPinned = isPinned
    }

    /// One-line label: first non-empty line of text, file names, or "Image".
    public var title: String {
        switch kind {
        case .text, .url:
            let lines = (text ?? "").split(whereSeparator: \.isNewline)
            let first = lines.lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return first ?? ""
        case .file:
            return (text ?? "")
                .split(separator: "\n")
                .map { (String($0) as NSString).lastPathComponent }
                .joined(separator: ", ")
        case .image:
            return "Image"
        }
    }
}

extension ClipItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clip"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let contentHash = Column(CodingKeys.contentHash)
        public static let rtfBlob = Column(CodingKeys.rtfBlob)
        public static let imageBlob = Column(CodingKeys.imageBlob)
        public static let lastUsedAt = Column(CodingKeys.lastUsedAt)
        public static let isPinned = Column(CodingKeys.isPinned)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
