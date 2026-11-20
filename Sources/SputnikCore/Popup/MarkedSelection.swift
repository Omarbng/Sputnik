/// Multi-select in the popup. Space adds or removes an item; each marked row shows its
/// position (1, 2, 3…), and ⌘↩ pastes them in that order.
public struct MarkedSelection: Equatable, Sendable {
    public private(set) var ids: [Int64] = []

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }

    public mutating func toggle(_ id: Int64) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
    }

    /// 1-based position, or nil if the item isn't marked.
    public func number(for id: Int64) -> Int? {
        ids.firstIndex(of: id).map { $0 + 1 }
    }

    /// Forgets items that no longer exist (for example, after a delete).
    public mutating func keep(only existing: Set<Int64>) {
        ids.removeAll { !existing.contains($0) }
    }

    public mutating func removeAll() {
        ids.removeAll()
    }
}
