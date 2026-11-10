import CryptoKit
import Foundation

enum ContentHash {
    static func hex(of data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    /// Dedupe key. Text-like kinds hash their stored text; images hash their PNG bytes.
    static func of(kind: ClipKind, text: String?, image: Data?) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        if let text { hasher.update(data: Data(text.utf8)) }
        if let image { hasher.update(data: image) }
        return hexString(hasher.finalize())
    }

    private static func hexString(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
