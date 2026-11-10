import Foundation

/// How much unpinned history to keep. Pinned items never expire and don't count toward the limit.
public struct RetentionPolicy: Sendable, Equatable {
    public var maxUnpinned: Int
    public var maxAgeDays: Int

    public init(maxUnpinned: Int = 500, maxAgeDays: Int = 30) {
        self.maxUnpinned = maxUnpinned
        self.maxAgeDays = maxAgeDays
    }

    /// IDs of unpinned items that are older than `maxAgeDays`, or beyond the newest `maxUnpinned`.
    public func expiredIDs(in items: [ClipItem], now: Date) -> [Int64] {
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        let unpinned = items
            .filter { !$0.isPinned }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
        return unpinned.enumerated().compactMap { index, item in
            (index >= maxUnpinned || item.lastUsedAt < cutoff) ? item.id : nil
        }
    }
}
