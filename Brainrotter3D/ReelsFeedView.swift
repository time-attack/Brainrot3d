import SwiftUI

struct ReelsFeedView: View {
    @Environment(AppModel.self) private var model
    @State private var activeID: String?
    @State private var muted = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.reels.isEmpty {
                ProgressView("Loading reels…")
                    .controlSize(.large)
                    .tint(.white)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(model.reels) { reel in
                            ReelCell(reel: reel, isActive: reel.id == activeID, muted: muted)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(reel.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $activeID)
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) { topBar }
        .ornament(attachmentAnchor: .scene(.bottom)) { bottomControls }
        .onChange(of: activeID) { _, new in onAdvance(to: new) }
        .onChange(of: model.reels.count) { _, _ in
            if activeID == nil { activeID = model.reels.first?.id }
        }
    }

    private var topBar: some View {
        HStack {
            Text("@\(model.username)").font(.headline)
            Spacer()
            Button { muted.toggle() } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 16).padding(.top, 10)
    }

    private var bottomControls: some View {
        HStack(spacing: 22) {
            Button { Task { await model.loadMore(reset: true); activeID = model.reels.first?.id } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) { model.logout() } label: {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .buttonStyle(.borderless)
        .padding(.horizontal, 26).padding(.vertical, 14)
        .glassBackgroundEffect()
    }

    /// When the active reel changes: register the view, and prefetch more near the end.
    private func onAdvance(to id: String?) {
        guard let id, let idx = model.reels.firstIndex(where: { $0.id == id }) else { return }
        model.markSeen(model.reels[idx])
        if idx >= model.reels.count - 3 {
            Task { await model.loadMore() }
        }
    }
}

private struct ReelCell: View {
    let reel: Reel
    let isActive: Bool
    let muted: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LoopingPlayerView(url: reel.videoURL, isActive: isActive, isMuted: muted)
                .ignoresSafeArea()

            LinearGradient(colors: [.clear, .black.opacity(0.7)],
                           startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    AsyncImage(url: reel.profilePic) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { Color.gray.opacity(0.3) }
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 1))

                    Text("@\(reel.username)").font(.subheadline.bold())
                    if reel.verified {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.caption)
                    }
                }
                if !reel.fullName.isEmpty {
                    Text(reel.fullName).font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                Text("⏱ \(reel.duration, specifier: "%.1f")s  \(reel.hasAudio ? "🔊" : "🔇")")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.bottom, 28)
        }
        .background(Color.black)
    }
}
