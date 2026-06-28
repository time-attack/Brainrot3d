import Foundation

struct Reel: Identifiable, Equatable {
    let pk: String
    let code: String?
    let username: String
    let fullName: String
    let verified: Bool
    let profilePic: URL?
    let videoURL: URL
    let thumbURL: URL?
    let duration: Double
    let hasAudio: Bool

    // Algorithm / ranking signals the feed attaches to every reel (see ALGORITHM_SIGNALS.md).
    let trackingTokenRaw: String?
    let loggingInfoToken: String?
    let rankedAt: String?
    let rankedPosition: Int?
    let tracking: TrackingInfo?

    var id: String { pk }
    var permalink: URL? { code.flatMap { URL(string: "https://www.instagram.com/reel/\($0)/") } }

    /// Build from a raw media dict found in the discovery stream. Returns nil if there's
    /// no playable video (the only thing this app cares about).
    init?(json m: [String: Any]) {
        guard let pkAny = m["pk"] else { return nil }
        let pkStr = String(describing: pkAny)
        let versions = (m["video_versions"] as? [[String: Any]]) ?? []
        let best = versions.max { ($0.area) < ($1.area) }
        guard let urlStr = best?["url"] as? String, let url = URL(string: urlStr) else { return nil }

        pk = pkStr
        code = m["code"] as? String
        videoURL = url

        let user = (m["user"] as? [String: Any]) ?? [:]
        username = (user["username"] as? String) ?? "?"
        fullName = (user["full_name"] as? String) ?? ""
        verified = (user["is_verified"] as? Bool) ?? false
        profilePic = (user["profile_pic_url"] as? String).flatMap(URL.init(string:))

        let candidates = ((m["image_versions2"] as? [String: Any])?["candidates"] as? [[String: Any]]) ?? []
        thumbURL = (candidates.max { $0.area < $1.area }?["url"] as? String).flatMap(URL.init(string:))

        duration = (m["video_duration"] as? Double) ?? 0
        hasAudio = (m["has_audio"] as? Bool) ?? false

        trackingTokenRaw = m["organic_tracking_token"] as? String
        loggingInfoToken = m["logging_info_token"] as? String
        if let r = m["ranked_at"] { rankedAt = String(describing: r) } else { rankedAt = nil }
        rankedPosition = (m["client_position"] as? Int) ?? (m["ranked_position"] as? Int)
        tracking = TrackingToken.decode(trackingTokenRaw)
    }
}

private extension Dictionary where Key == String, Value == Any {
    /// width * height, for picking the highest-resolution version.
    var area: Int {
        let w = (self["width"] as? Int) ?? 0
        let h = (self["height"] as? Int) ?? 0
        return w * h
    }
}

/// Parses the newline/concatenated-JSON "ndjson" body of `clips/discover/stream/` and
/// walks it for reel media + the paging token — ported from `reels_downloader.py`.
enum NDJSON {

    /// Split a stream of concatenated top-level JSON values (brace-matched, string-aware).
    static func parse(_ text: String) -> [Any] {
        let b = Array(text.utf8)
        let n = b.count
        var i = 0
        var out: [Any] = []
        while i < n {
            while i < n, b[i] == 0x20 || b[i] == 0x0a || b[i] == 0x0d || b[i] == 0x09 { i += 1 }
            if i >= n { break }
            let start = i
            var depth = 0, inStr = false, esc = false, started = false
            while i < n {
                let c = b[i]
                if inStr {
                    if esc { esc = false }
                    else if c == 0x5c { esc = true }
                    else if c == 0x22 { inStr = false }
                } else {
                    if c == 0x22 { inStr = true }
                    else if c == 0x7b || c == 0x5b { depth += 1; started = true }
                    else if c == 0x7d || c == 0x5d { depth -= 1 }
                }
                i += 1
                if started && depth == 0 { break }
            }
            if i <= start { break }
            let slice = Data(b[start..<i])
            if let obj = try? JSONSerialization.jsonObject(with: slice) { out.append(obj) }
        }
        return out
    }

    /// Recursively collect dicts that have both `video_versions` and `pk` (a reel), deduped.
    static func findReels(_ objs: [Any]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var seen = Set<String>()
        func visit(_ o: Any) {
            if let d = o as? [String: Any] {
                if d["video_versions"] != nil, let pk = d["pk"] {
                    let key = String(describing: pk)
                    if !seen.contains(key) { seen.insert(key); out.append(d) }
                }
                for v in d.values { visit(v) }
            } else if let a = o as? [Any] {
                for v in a { visit(v) }
            }
        }
        objs.forEach(visit)
        return out
    }

    /// First of paging_token / next_max_id / max_id found anywhere in the tree.
    static func findToken(_ objs: [Any]) -> String? {
        var box: [String: String] = [:]
        func visit(_ o: Any) {
            if let d = o as? [String: Any] {
                for k in ["paging_token", "next_max_id", "max_id"] {
                    if box[k] == nil, let v = d[k] as? String, !v.isEmpty { box[k] = v }
                }
                for v in d.values { visit(v) }
            } else if let a = o as? [Any] {
                for v in a { visit(v) }
            }
        }
        objs.forEach(visit)
        return box["paging_token"] ?? box["next_max_id"] ?? box["max_id"]
    }
}
