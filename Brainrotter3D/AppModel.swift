import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case launching
        case login
        case twoFactor(TwoFactorInfo)
        case feed
    }

    var phase: Phase = .launching
    var client = IGClient()
    var loginError: String?
    var busy = false

    // Feed state
    var reels: [Reel] = []
    private var token: String?
    private var seen = Set<String>()
    private var loadingMore = false
    var feedExhausted = false

    /// When ON, advancing a reel uploads the confirmed-live watch signal
    /// (`clips/write_seen_state/`) to Instagram. When OFF you watch privately and nothing
    /// is reported. Default OFF — observe, don't fabricate.
    var sendAnalytics = false
    /// Set when the most recent advance actually uploaded a signal (for the UI).
    var lastSignalSent = false

    /// Live like/comment state per reel pk (optimistic, refreshed from media_info).
    struct Engagement { var liked: Bool; var likeCount: Int; var commentCount: Int }
    var engagement: [String: Engagement] = [:]

    func engagement(for reel: Reel) -> Engagement {
        engagement[reel.pk] ?? Engagement(liked: reel.hasLiked, likeCount: reel.likeCount, commentCount: reel.commentCount)
    }

    var username: String { client.username ?? "" }

    // MARK: Launch / resume

    func start() async {
        client.loadState()
        if await client.validateSession() {
            phase = .feed
            await loadMore(reset: true)
        } else {
            IGClient.clearState()
            client = IGClient()                      // fresh client, same trusted device seed
            phase = .login
        }
    }

    // MARK: Auth actions

    func login(username: String, password: String) async {
        loginError = nil
        busy = true
        defer { busy = false }
        do {
            switch try await client.login(username: username, password: password) {
            case .success:
                client.saveState()
                phase = .feed
                await loadMore(reset: true)
            case .twoFactor(let info):
                phase = .twoFactor(info)
            case .failure(let msg):
                loginError = msg
            }
        } catch {
            loginError = error.localizedDescription
        }
    }

    func sendCode(info: TwoFactorInfo, method: String) async {
        if method == "1" { try? await client.sendTwoFactorSMS(info) }
        else if method == "6" { try? await client.sendTwoFactorWhatsApp(info) }
    }

    func submitCode(_ code: String, info: TwoFactorInfo, method: String) async {
        loginError = nil
        busy = true
        defer { busy = false }
        do {
            switch try await client.twoFactorLogin(code: code, info: info, method: method) {
            case .success:
                client.saveState()
                phase = .feed
                await loadMore(reset: true)
            case .failure(let msg):
                loginError = msg
            case .twoFactor:
                loginError = "still needs verification"
            }
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout() {
        IGClient.clearState()
        client = IGClient()
        reels = []; token = nil; seen = []; feedExhausted = false
        phase = .login
    }

    // MARK: Feed

    func loadMore(reset: Bool = false) async {
        if reset { token = nil; seen = []; reels = []; feedExhausted = false }
        if loadingMore || (feedExhausted && !reset) { return }
        loadingMore = true
        defer { loadingMore = false }

        var added = 0, tries = 0
        while added < 6, tries < 3 {
            tries += 1
            guard let page = try? await client.reelsDiscover(maxID: token), page.status == 200 else { break }
            for r in page.reels where !seen.contains(r.pk) {
                seen.insert(r.pk); reels.append(r); added += 1
            }
            guard let next = page.token, next != token else { break }
            token = next
        }
        if added == 0 { feedExhausted = true }
    }

    func markSeen(_ reel: Reel) {
        guard sendAnalytics else { lastSignalSent = false; return }
        lastSignalSent = true
        Task { await client.writeSeenState(pk: reel.pk) }
    }

    // MARK: Engagement

    /// Refresh real like/comment counts for a reel from media_info.
    func refreshMeta(_ reel: Reel) {
        Task {
            guard let meta = await client.mediaMeta(reel.pk) else { return }
            engagement[reel.pk] = Engagement(liked: meta.hasLiked,
                                             likeCount: meta.likeCount,
                                             commentCount: meta.commentCount)
        }
    }

    /// Optimistically toggle like, then send to Instagram.
    func toggleLike(_ reel: Reel) {
        var e = engagement(for: reel)
        let on = !e.liked
        e.liked = on
        e.likeCount = max(0, e.likeCount + (on ? 1 : -1))
        engagement[reel.pk] = e
        Task { _ = await client.like(reel.pk, on: on) }
    }

    /// Force a like on (for double-tap), no toggle off.
    func likeOn(_ reel: Reel) {
        var e = engagement(for: reel)
        guard !e.liked else { return }
        e.liked = true
        e.likeCount += 1
        engagement[reel.pk] = e
        Task { _ = await client.like(reel.pk, on: true) }
    }

    func setCommentCount(_ reel: Reel, _ count: Int) {
        var e = engagement(for: reel)
        e.commentCount = count
        engagement[reel.pk] = e
    }
}

// Convenience pass-throughs so views can await the client via the model.
extension AppModel {
    func loadComments(_ reel: Reel, maxID: String? = nil) async -> CommentsPage {
        await client.comments(reel.pk, maxID: maxID)
    }
    func loadReplies(_ reel: Reel, commentID: String) async -> [IGComment] {
        await client.replies(reel.pk, commentID: commentID)
    }
    func toggleCommentLike(_ commentID: String, on: Bool) async -> Bool {
        await client.likeComment(commentID, on: on)
    }
    func loadLikers(_ reel: Reel) async -> [IGUser] {
        await client.likers(reel.pk)
    }
    func loadRecipients(_ query: String) async -> [Recipient] {
        await client.rankedRecipients(query: query)
    }
    func share(_ reel: Reel, threadIDs: [String], userIDs: [String], text: String) async -> Bool {
        await client.shareMedia(reel.pk, threadIDs: threadIDs, userIDs: userIDs, text: text)
    }
}
