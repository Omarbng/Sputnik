import Foundation

/// Files in `blobs/`, named by content hash, so identical content is stored once.
public struct BlobStore: Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Writes `data` as `<sha256>.<ext>` unless it already exists. Returns the file name.
    @discardableResult
    public func store(_ data: Data, fileExtension: String) throws -> String {
        let name = "\(ContentHash.hex(of: data)).\(fileExtension)"
        let url = url(for: name)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try data.write(to: url, options: .atomic)
        }
        return name
    }

    public func url(for name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }

    public func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path(percentEncoded: false))
    }

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
