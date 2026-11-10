import ClipDockCore
import Foundation

/// Stores captures one at a time, in order, off the main thread. That covers image
/// conversion, the size check, hashing, and blob and database writes.
final class CapturePipeline: Sendable {
    private struct Job: Sendable {
        let clip: CapturedClip
        let rules: SkipRules
        let retention: RetentionPolicy
    }

    private let continuation: AsyncStream<Job>.Continuation

    init(database: HistoryDatabase, onStored: @escaping @MainActor @Sendable (HistoryChange) -> Void) {
        let (jobs, continuation) = AsyncStream.makeStream(of: Job.self)
        self.continuation = continuation
        Task.detached(priority: .utility) {
            for await job in jobs {
                if let change = Self.process(job, database: database) {
                    await onStored(change)
                }
            }
        }
    }

    deinit {
        continuation.finish()
    }

    func submit(_ clip: CapturedClip, rules: SkipRules, retention: RetentionPolicy) {
        continuation.yield(Job(clip: clip, rules: rules, retention: retention))
    }

    private static func process(_ job: Job, database: HistoryDatabase) -> HistoryChange? {
        guard let clip = job.clip.normalized() else {
            Log.capture.notice("skipped reason=undecodableImage")
            return nil
        }
        if let reason = job.rules.reasonAfterReading(byteSize: clip.byteSize) {
            Log.capture.notice("skipped reason=\(reason.logName, privacy: .public) bytes=\(clip.byteSize, privacy: .public)")
            return nil
        }
        do {
            let change = try database.ingest(clip, retention: job.retention)
            Log.capture.notice("""
                stored id=\(change.item.id ?? -1, privacy: .public) \
                kind=\(clip.kind.rawValue, privacy: .public) \
                bytes=\(clip.byteSize, privacy: .public) \
                duplicate=\(change.wasDuplicate, privacy: .public) \
                expired=\(change.removedIDs.count, privacy: .public)
                """)
            return change
        } catch {
            Log.storage.error("ingest failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
