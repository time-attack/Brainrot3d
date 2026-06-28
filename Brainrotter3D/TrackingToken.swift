import Foundation

/// Decoded view of a reel's `organic_tracking_token` — the linkage token Instagram attaches
/// to every reel so a later watch-time/impression event ties back to this exact reel + viewer.
/// Structure (reverse-engineered, see ALGORITHM_SIGNALS.md):
///   { version, payload: { is_analytics_tracked, uuid,
///       server_token: "<ts_ms>|<media_pk>|<viewer_user_id>|<hmac>" } }
struct TrackingInfo: Equatable {
    var raw: String
    var servedAtMS: String?
    var mediaPK: String?
    var viewerID: String?
    var isAnalyticsTracked: Bool

    var servedAtDate: Date? {
        guard let ms = servedAtMS, let v = Double(ms) else { return nil }
        return Date(timeIntervalSince1970: v / 1000)
    }
}

enum TrackingToken {
    /// Best-effort decode. The token is base64 (std or url-safe) of the JSON above; if it
    /// doesn't decode we still return the raw string so the panel can show something.
    static func decode(_ token: String?) -> TrackingInfo? {
        guard let token, !token.isEmpty else { return nil }
        guard let data = base64Flexible(token),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else {
            return TrackingInfo(raw: token, servedAtMS: nil, mediaPK: nil,
                                viewerID: nil, isAnalyticsTracked: false)
        }
        let analytics = (payload["is_analytics_tracked"] as? Bool) ?? false
        let server = (payload["server_token"] as? String) ?? ""
        let parts = server.split(separator: "|").map(String.init)
        return TrackingInfo(
            raw: token,
            servedAtMS: parts.indices.contains(0) ? parts[0] : nil,
            mediaPK: parts.indices.contains(1) ? parts[1] : nil,
            viewerID: parts.indices.contains(2) ? parts[2] : nil,
            isAnalyticsTracked: analytics
        )
    }

    private static func base64Flexible(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}
