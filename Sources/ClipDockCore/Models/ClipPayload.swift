import Foundation

/// The content we keep from one pasteboard change.
public enum ClipPayload: Sendable, Equatable {
    /// Plain text, with RTF kept alongside when the source provided it.
    case text(String, rtf: Data?)
    /// A single web URL.
    case url(String)
    /// File URLs, stored as paths.
    case files([String])
    /// Image bytes. `isPNG == false` means it still needs converting (see `CapturedClip.normalized()`).
    case image(Data, isPNG: Bool)

    /// Classifies a copied string: a lone http(s) URL becomes `.url`, anything else `.text`.
    public static func fromText(_ string: String, rtf: Data?) -> ClipPayload {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return WebURL.isWebURL(trimmed) ? .url(trimmed) : .text(string, rtf: rtf)
    }
}

enum WebURL {
    /// True for a single http(s) URL with a host and no whitespace.
    static func isWebURL(_ string: String) -> Bool {
        guard !string.isEmpty,
              string.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else { return false }
        return true
    }
}
