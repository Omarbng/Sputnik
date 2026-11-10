import GRDB

/// What a history item holds.
public enum ClipKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case text
    case url
    case image
    case file
}
