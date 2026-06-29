import Foundation

// MARK: - Models

struct IGUser: Identifiable, Equatable {
    let username: String
    let fullName: String
    let verified: Bool
    let picURL: URL?
    var id: String { username }

    init(_ u: [String: Any]) {
        username = (u["username"] as? String) ?? "?"
        fullName = (u["full_name"] as? String) ?? ""
        verified = (u["is_verified"] as? Bool) ?? false
        picURL = (u["profile_pic_url"] as? String).flatMap(URL.init(string:))
    }
}

struct IGComment: Identifiable, Equatable {
    let pk: String
    let text: String
    let gifURL: URL?
    var likeCount: Int
    var hasLiked: Bool
    let replyCount: Int
    let createdAt: Double?
    let username: String
    let fullName: String
    let verified: Bool
    let profilePic: URL?
    var id: String { pk }

    init(_ cc: [String: Any]) {
        pk = String(describing: cc["pk"] ?? cc["pk_id"] ?? "")
        text = (cc["text"] as? String) ?? ""
        likeCount = (cc["comment_like_count"] as? Int) ?? 0
        hasLiked = (cc["has_liked_comment"] as? Bool) ?? false
        replyCount = (cc["child_comment_count"] as? Int) ?? 0
        createdAt = (cc["created_at"] as? Double) ?? (cc["created_at"] as? Int).map(Double.init)

        let u = (cc["user"] as? [String: Any]) ?? [:]
        username = (u["username"] as? String) ?? "?"
        fullName = (u["full_name"] as? String) ?? ""
        verified = (u["is_verified"] as? Bool) ?? false
        profilePic = (u["profile_pic_url"] as? String).flatMap(URL.init(string:))

        // animated/gif comments
        var gif: String?
        let imgs = ((cc["animated_media"] as? [String: Any])?["images"] as? [String: Any])
        for k in ["fixed_height", "fixed_height_downsampled", "original"] {
            let img = imgs?[k] as? [String: Any]
            if let w = img?["webp"] as? String { gif = w; break }
            if let url = img?["url"] as? String { gif = url; break }
        }
        gifURL = gif.flatMap(URL.init(string:))
    }
}

struct CommentsPage {
    var comments: [IGComment]
    var nextMaxID: String?
    var count: Int?
    var hasMore: Bool
}

struct MediaMeta {
    let likeCount: Int
    let commentCount: Int
    let playCount: Int?
    let hasLiked: Bool
    let caption: String
    let facepile: [IGUser]
}

struct Recipient: Identifiable, Equatable {
    enum Kind { case user, thread }
    let kind: Kind
    let id: String          // user pk or thread id
    let name: String
    let fullName: String
    let picURL: URL?
    let verified: Bool
}

struct IGProfile: Equatable {
    let userID: String
    let username: String
    let fullName: String
    let bio: String
    let picURL: URL?
    let verified: Bool
    let followerCount: Int?
    let followingCount: Int?
}

// MARK: - Engagement API (likes / comments / replies / likers / share)

extension IGClient {

    func mediaMeta(_ mediaID: String) async -> MediaMeta? {
        guard let (data, http) = try? await get("/api/v1/media/\(mediaID)/info/"),
              http.statusCode == 200,
              let it = (jsonObject(data)["items"] as? [[String: Any]])?.first else { return nil }
        let fp = (it["facepile_top_likers"] as? [[String: Any]]) ?? []
        return MediaMeta(
            likeCount: (it["like_count"] as? Int) ?? 0,
            commentCount: (it["comment_count"] as? Int) ?? 0,
            playCount: (it["play_count"] as? Int) ?? (it["view_count"] as? Int),
            hasLiked: (it["has_liked"] as? Bool) ?? false,
            caption: ((it["caption"] as? [String: Any])?["text"] as? String) ?? "",
            facepile: fp.prefix(3).map(IGUser.init)
        )
    }

    /// Like or unlike a reel. POST /api/v1/media/{id}/{like|unlike}/
    func like(_ mediaID: String, on: Bool) async -> Bool {
        let action = on ? "like" : "unlike"
        let data = ["media_id": mediaID, "_uuid": uuid, "container_module": "clips_viewer_clips_tab"]
        guard let (_, http) = try? await post("/api/v1/media/\(mediaID)/\(action)/", data: data) else { return false }
        return http.statusCode == 200
    }

    func comments(_ mediaID: String, maxID: String? = nil) async -> CommentsPage {
        var params = ["can_support_threading": "true", "permalink_enabled": "false"]
        if let maxID { params["max_id"] = maxID }
        guard let (data, http) = try? await get("/api/v1/media/\(mediaID)/comments/", params: params),
              http.statusCode == 200 else {
            return CommentsPage(comments: [], nextMaxID: nil, count: nil, hasMore: false)
        }
        let j = jsonObject(data)
        let list = (j["comments"] as? [[String: Any]] ?? []).map(IGComment.init)
        return CommentsPage(comments: list,
                            nextMaxID: j["next_max_id"] as? String,
                            count: j["comment_count"] as? Int,
                            hasMore: (j["has_more_comments"] as? Bool) ?? false)
    }

    func replies(_ mediaID: String, commentID: String) async -> [IGComment] {
        guard let (data, http) = try? await get("/api/v1/media/\(mediaID)/comments/\(commentID)/child_comments/"),
              http.statusCode == 200 else { return [] }
        return (jsonObject(data)["child_comments"] as? [[String: Any]] ?? []).map(IGComment.init)
    }

    /// Like or unlike a comment. POST /api/v1/media/{comment_id}/{comment_like|comment_unlike}/
    func likeComment(_ commentID: String, on: Bool) async -> Bool {
        let action = on ? "comment_like" : "comment_unlike"
        guard let (_, http) = try? await post("/api/v1/media/\(commentID)/\(action)/", data: ["_uuid": uuid]) else { return false }
        return http.statusCode == 200
    }

    func likers(_ mediaID: String) async -> [IGUser] {
        guard let (data, http) = try? await get("/api/v1/media/\(mediaID)/likers/"),
              http.statusCode == 200 else { return [] }
        return (jsonObject(data)["users"] as? [[String: Any]] ?? []).map(IGUser.init)
    }

    func rankedRecipients(query: String = "") async -> [Recipient] {
        var params = ["mode": "reshare", "show_threads": "true"]
        if !query.isEmpty { params["query"] = query }
        guard let (data, http) = try? await get("/api/v1/direct_v2/ranked_recipients/", params: params),
              http.statusCode == 200 else { return [] }
        var out: [Recipient] = []
        for x in (jsonObject(data)["ranked_recipients"] as? [[String: Any]] ?? []) {
            if let u = x["user"] as? [String: Any] {
                out.append(Recipient(kind: .user,
                                     id: String(describing: u["pk"] ?? ""),
                                     name: (u["username"] as? String) ?? "?",
                                     fullName: (u["full_name"] as? String) ?? "",
                                     picURL: (u["profile_pic_url"] as? String).flatMap(URL.init(string:)),
                                     verified: (u["is_verified"] as? Bool) ?? false))
            } else if let th = x["thread"] as? [String: Any] {
                let members = (th["users"] as? [[String: Any]]) ?? []
                let title = (th["thread_title"] as? String)
                    ?? members.prefix(3).compactMap { $0["username"] as? String }.joined(separator: ", ")
                out.append(Recipient(kind: .thread,
                                     id: String(describing: th["thread_id"] ?? ""),
                                     name: title,
                                     fullName: "Group",
                                     picURL: (members.first?["profile_pic_url"] as? String).flatMap(URL.init(string:)),
                                     verified: false))
            }
        }
        return out
    }

    /// Share a reel into DM threads / to users. POST direct_v2/threads/broadcast/media_share/
    func shareMedia(_ mediaID: String, threadIDs: [String], userIDs: [String], text: String) async -> Bool {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        var data: [String: String] = [
            "action": "send_item",
            "media_id": mediaID,
            "unified_broadcast_format": "1",
            "client_context": "\(uuid)_\(ms)",
            "_uuid": uuid,
        ]
        if !threadIDs.isEmpty {
            data["thread_ids"] = "[" + threadIDs.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        }
        if !userIDs.isEmpty {
            data["recipient_users"] = "[[" + userIDs.joined(separator: ",") + "]]"
        }
        if !text.isEmpty { data["text"] = text }
        guard let (_, http) = try? await post("/api/v1/direct_v2/threads/broadcast/media_share/", data: data) else { return false }
        return http.statusCode == 200
    }

    // MARK: Creator profile + their reels

    /// Resolve a username to a profile via web_profile_info (with a mobile fallback).
    func profile(username: String) async -> IGProfile? {
        if let (data, http) = try? await get("/api/v1/users/web_profile_info/", params: ["username": username]),
           http.statusCode == 200,
           let u = ((jsonObject(data)["data"] as? [String: Any])?["user"] as? [String: Any]) {
            return IGProfile(
                userID: String(describing: u["id"] ?? u["pk"] ?? ""),
                username: (u["username"] as? String) ?? username,
                fullName: (u["full_name"] as? String) ?? "",
                bio: (u["biography"] as? String) ?? "",
                picURL: (u["profile_pic_url"] as? String).flatMap(URL.init(string:)),
                verified: (u["is_verified"] as? Bool) ?? false,
                followerCount: (u["edge_followed_by"] as? [String: Any])?["count"] as? Int,
                followingCount: (u["edge_follow"] as? [String: Any])?["count"] as? Int)
        }
        // mobile fallback: usernameinfo
        guard let (data, http) = try? await get("/api/v1/users/\(username)/usernameinfo/"),
              http.statusCode == 200,
              let u = jsonObject(data)["user"] as? [String: Any] else { return nil }
        return IGProfile(
            userID: String(describing: u["pk"] ?? ""),
            username: (u["username"] as? String) ?? username,
            fullName: (u["full_name"] as? String) ?? "",
            bio: (u["biography"] as? String) ?? "",
            picURL: (u["profile_pic_url"] as? String).flatMap(URL.init(string:)),
            verified: (u["is_verified"] as? Bool) ?? false,
            followerCount: u["follower_count"] as? Int,
            followingCount: u["following_count"] as? Int)
    }

    /// A creator's own reels. POST clips/user/
    func userReels(userID: String, maxID: String? = nil) async -> (reels: [Reel], nextMaxID: String?) {
        var data: [String: String] = ["target_user_id": userID, "page_size": "12",
                                       "include_feed_video": "true", "_uuid": uuid]
        if let maxID { data["max_id"] = maxID }
        guard let (raw, http) = try? await post("/api/v1/clips/user/", data: data),
              http.statusCode == 200 else { return ([], nil) }
        let j = jsonObject(raw)
        let items = (j["items"] as? [[String: Any]]) ?? []
        let reels = items.compactMap { item -> Reel? in
            Reel(json: (item["media"] as? [String: Any]) ?? item)
        }
        let paging = j["paging_info"] as? [String: Any]
        let next = (paging?["max_id"] as? String) ?? (j["max_id"] as? String)
        return (reels, next)
    }
}
