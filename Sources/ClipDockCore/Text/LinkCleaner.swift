import Foundation

/// Removes tracking parameters from a copied link (`utm_…`, `fbclid`, `gclid` …), so what you
/// paste is the plain address. Everything else in the link stays exactly as it was.
public enum LinkCleaner {
    /// Parameter names removed on every site.
    static let trackingNames: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid",
        "ttclid", "li_fat_id", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "igshid",
        "vero_id", "oly_enc_id", "oly_anon_id", "rb_clickid", "_ga", "_gl", "s_cid", "ref_src",
        "ref_url", "srsltid", "epik", "sc_cid", "wickedid", "trk_contact", "trk_msg", "trk_module",
    ]
    /// Parameter-name prefixes removed on every site.
    static let trackingPrefixes = ["utm_", "pk_", "mtm_", "hsa_", "matomo_"]
    /// Parameters that only track on particular sites (elsewhere they can mean something).
    static let siteNames: [(host: String, names: Set<String>)] = [
        ("youtube.com", ["si", "feature", "pp"]),
        ("youtu.be", ["si", "feature"]),
        ("spotify.com", ["si", "context"]),
        ("instagram.com", ["igsh", "img_index"]),
        ("threads.net", ["igsh"]),
        ("x.com", ["s", "t"]),
        ("twitter.com", ["s", "t"]),
        ("linkedin.com", ["trk", "trackingId", "lipi", "midToken", "midSig", "trkEmail", "eid"]),
        ("tiktok.com", ["_r", "_t", "is_from_webapp", "sender_device"]),
        ("facebook.com", ["mibextid", "rdid", "share_url"]),
        ("reddit.com", ["share_id", "utm_name", "rdt"]),
    ]

    /// The link without tracking parameters, or nil when there's nothing to remove (or it
    /// isn't a single http(s) link).
    public static func clean(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WebURL.isWebURL(trimmed),
              var components = URLComponents(string: trimmed),
              let items = components.percentEncodedQueryItems, !items.isEmpty
        else { return nil }
        let host = components.host?.lowercased() ?? ""
        let siteSpecific = siteNames
            .filter { host == $0.host || host.hasSuffix("." + $0.host) }
            .reduce(into: Set<String>()) { $0.formUnion($1.names) }
        let kept = items.filter { item in
            let name = item.name.removingPercentEncoding ?? item.name
            return !isTracking(name.lowercased(), siteSpecific: siteSpecific, original: name)
        }
        guard kept.count < items.count else { return nil }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string
    }

    private static func isTracking(_ lowered: String, siteSpecific: Set<String>, original: String) -> Bool {
        trackingNames.contains(lowered)
            || trackingPrefixes.contains { lowered.hasPrefix($0) }
            || siteSpecific.contains(original) || siteSpecific.contains(lowered)
    }
}
