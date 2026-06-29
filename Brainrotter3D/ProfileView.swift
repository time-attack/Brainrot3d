import SwiftUI

/// A creator's profile: header + a grid of their reels (clips/user/). Tap a reel to play it
/// full-window in a vertical paging feed.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let username: String

    @State private var profile: IGProfile?
    @State private var reels: [Reel] = []
    @State private var nextMaxID: String?
    @State private var loading = true
    @State private var playingID: String?

    private let cols = [GridItem(.flexible(), spacing: 3),
                        GridItem(.flexible(), spacing: 3),
                        GridItem(.flexible(), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                header
                if loading && reels.isEmpty {
                    ProgressView().padding(40)
                } else if reels.isEmpty {
                    ContentUnavailableView("No reels", systemImage: "film.stack")
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: cols, spacing: 3) {
                        ForEach(reels) { reel in
                            Button { playingID = reel.id } label: { thumb(reel) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 3)
                    if nextMaxID != nil {
                        Button("Load more") { Task { await loadReels() } }.padding()
                    }
                }
            }
            .navigationTitle("@\(username)")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 520, minHeight: 640)
        .task { await load() }
        .fullScreenCover(item: Binding(get: { playingID.map { IDBox(id: $0) } },
                                       set: { playingID = $0?.id })) { box in
            ProfilePlayer(reels: reels, startID: box.id) { playingID = nil }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            AsyncImage(url: profile?.picURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
                .frame(width: 88, height: 88).clipShape(Circle())
            HStack(spacing: 5) {
                Text(profile?.fullName.isEmpty == false ? profile!.fullName : "@\(username)").font(.headline)
                if profile?.verified == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue) }
            }
            if let p = profile, !p.bio.isEmpty {
                Text(p.bio).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            HStack(spacing: 26) {
                stat(reels.count, "reels")
                if let f = profile?.followerCount { stat(f, "followers") }
                if let f = profile?.followingCount { stat(f, "following") }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 14)
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(short(n)).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func thumb(_ reel: Reel) -> some View {
        AsyncImage(url: reel.thumbURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.62, contentMode: .fill)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Image(systemName: "play.fill").font(.caption2).foregroundStyle(.white)
                    .padding(5).shadow(radius: 2)
            }
    }

    private func load() async {
        loading = true
        profile = await model.loadProfile(username)
        if let id = profile?.userID, !id.isEmpty {
            let page = await model.loadUserReels(id)
            reels = page.reels; nextMaxID = page.nextMaxID
        }
        loading = false
    }

    private func loadReels() async {
        guard let id = profile?.userID else { return }
        let page = await model.loadUserReels(id, maxID: nextMaxID)
        reels += page.reels; nextMaxID = page.nextMaxID
    }

    private func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct IDBox: Identifiable { let id: String }

/// Full-window vertical paging player for a creator's reels, reusing the main ReelCell.
private struct ProfilePlayer: View {
    let reels: [Reel]
    let startID: String
    var onClose: () -> Void
    @State private var activeID: String?
    @State private var paused = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(reels) { reel in
                        ReelCell(reel: reel,
                                 isActive: reel.id == activeID,
                                 muted: false,
                                 paused: paused && reel.id == activeID,
                                 togglePause: { paused.toggle() })
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(reel.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeID)
            .ignoresSafeArea()
            .onChange(of: activeID) { _, _ in paused = false }

            Button { onClose() } label: {
                Image(systemName: "xmark").font(.headline).padding(10)
            }
            .buttonStyle(.borderless)
            .background(.ultraThinMaterial, in: Circle())
            .padding(16)
        }
        .onAppear { activeID = startID }
    }
}
