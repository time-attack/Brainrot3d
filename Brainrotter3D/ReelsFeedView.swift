import SwiftUI

struct ReelsFeedView: View {
    @Environment(AppModel.self) private var model
    @State private var activeID: String?
    @State private var muted = false
    @State private var paused = false
    @State private var showSignals = false
    @State private var watchSeconds = 0.0

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var activeReel: Reel? { model.reels.first { $0.id == activeID } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.reels.isEmpty {
                ProgressView("Loading reels…").controlSize(.large).tint(.white)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(model.reels) { reel in
                            ReelCell(reel: reel,
                                     isActive: reel.id == activeID,
                                     muted: muted,
                                     paused: paused && reel.id == activeID)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .contentShape(Rectangle())
                                .onTapGesture { paused.toggle() }
                                .id(reel.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $activeID)
                .ignoresSafeArea()
            }

            if showSignals, let reel = activeReel {
                AlgorithmPanel(reel: reel,
                               watchSeconds: watchSeconds,
                               audioOn: !muted && reel.hasAudio,
                               sending: model.sendAnalytics) {
                    withAnimation { showSignals = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 64).padding(.trailing, 14)
            }
        }
        .overlay(alignment: .top) { topBar }
        .ornament(attachmentAnchor: .scene(.bottom)) { bottomControls }
        .onChange(of: activeID) { _, new in
            paused = false; watchSeconds = 0; onAdvance(to: new)
        }
        .onChange(of: model.reels.count) { _, _ in
            if activeID == nil { activeID = model.reels.first?.id }
        }
        .onReceive(tick) { _ in
            if activeID != nil && !paused { watchSeconds += 0.5 }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("@\(model.username)").font(.headline)
            Spacer()

            // Analytics signal toggle (send the real watch signal to IG, or watch privately).
            Button { model.sendAnalytics.toggle() } label: {
                Label(model.sendAnalytics ? "Signals ON" : "Private",
                      systemImage: model.sendAnalytics ? "dot.radiowaves.left.and.right" : "eye.slash")
                    .font(.caption.bold())
            }
            .tint(model.sendAnalytics ? .green : .secondary)
            .buttonStyle(.bordered)

            Button { withAnimation { showSignals.toggle() } } label: {
                Image(systemName: "chart.bar.doc.horizontal")
            }
            .buttonStyle(.borderless)

            Button { muted.toggle() } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 14).padding(.top, 10)
    }

    // MARK: Bottom ornament (pause is the centerpiece)

    private var bottomControls: some View {
        HStack(spacing: 20) {
            Button { Task { await model.loadMore(reset: true); activeID = model.reels.first?.id } } label: {
                Image(systemName: "arrow.clockwise")
            }

            Button { paused.toggle() } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.title)
                    .frame(width: 30)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) { model.logout() } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
        }
        .font(.title2)
        .buttonStyle(.borderless)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .glassBackgroundEffect()
    }

    private func onAdvance(to id: String?) {
        guard let id, let idx = model.reels.firstIndex(where: { $0.id == id }) else { return }
        model.markSeen(model.reels[idx])
        if idx >= model.reels.count - 3 { Task { await model.loadMore() } }
    }
}

// MARK: - Reel cell

private struct ReelCell: View {
    let reel: Reel
    let isActive: Bool
    let muted: Bool
    let paused: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LoopingPlayerView(url: reel.videoURL, isActive: isActive, isMuted: muted, isPaused: paused)
                .ignoresSafeArea()

            // Big play glyph while paused.
            if paused {
                Image(systemName: "play.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    AsyncImage(url: reel.profilePic) { img in img.resizable().scaledToFill() }
                        placeholder: { Color.gray.opacity(0.3) }
                        .frame(width: 34, height: 34).clipShape(Circle())
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

// MARK: - Algorithm signals panel

private struct AlgorithmPanel: View {
    let reel: Reel
    let watchSeconds: Double
    let audioOn: Bool
    let sending: Bool
    var onClose: () -> Void

    private var completion: Double {
        guard reel.duration > 0 else { return 0 }
        return min(1, watchSeconds / reel.duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Algorithm signals", systemImage: "chart.bar.doc.horizontal").font(.headline)
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }

            // What your watch teaches the ranker right now (measured locally, not fabricated).
            signalGroup("This watch") {
                row("Watch time", String(format: "%.1f s", watchSeconds))
                row("Completion", String(format: "%.0f%%", completion * 100))
                row("Audio", audioOn ? "on" : "off")
                row("Visibility", "100%")
                HStack {
                    Image(systemName: sending ? "dot.radiowaves.left.and.right" : "eye.slash")
                    Text(sending ? "Reporting watch signal to Instagram"
                                 : "Private — no signal sent")
                        .font(.caption)
                }
                .foregroundStyle(sending ? .green : .secondary)
                .padding(.top, 2)
            }

            // The ranking context the feed served this reel under.
            signalGroup("Served context") {
                if let t = reel.tracking {
                    if let pk = t.mediaPK { row("Media PK", pk) }
                    if let v = t.viewerID { row("Viewer ID", v) }
                    if let d = t.servedAtDate {
                        row("Served at", d.formatted(date: .omitted, time: .standard))
                    }
                    row("Analytics-tracked", t.isAnalyticsTracked ? "yes" : "no")
                }
                if let r = reel.rankedAt { row("ranked_at", r) }
                if let p = reel.rankedPosition { row("Feed position", "#\(p)") }
                if let lit = reel.loggingInfoToken { row("logging token", String(lit.prefix(16)) + "…") }
                if reel.tracking == nil && reel.rankedAt == nil {
                    Text("No ranking tokens on this item.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 320, alignment: .leading)
        .padding(18)
        .glassBackgroundEffect()
    }

    private func signalGroup(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
        }
    }
}
