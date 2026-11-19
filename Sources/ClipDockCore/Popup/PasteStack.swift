/// "Paste one by one": marked items wait in order, and each ⌘V Omar presses in any app pastes
/// the next one. Handy for filling in forms.
public struct PasteStack: Sendable, Equatable {
    public let ids: [Int64]
    /// The item on the clipboard now (what the next ⌘V pastes).
    public private(set) var position = 0

    public init?(ids: [Int64]) {
        guard ids.count >= 2 else { return nil }
        self.ids = ids
    }

    public var current: Int64? { ids.indices.contains(position) ? ids[position] : nil }
    public var isFinished: Bool { position >= ids.count }

    /// After a paste: moves on and returns the next item, or nil when the stack is used up.
    public mutating func advance() -> Int64? {
        guard !isFinished else { return nil }
        position += 1
        return current
    }

    /// "2 of 3", for the HUD (1-based, the item on the clipboard).
    public var progress: String { "\(min(position + 1, ids.count)) of \(ids.count)" }
}
