import SwiftUI
import AVFoundation

/// A seamless looping video view (AVQueuePlayer + AVPlayerLooper). Plays only while
/// `isActive`, so just the on-screen reel runs.
struct LoopingPlayerView: UIViewRepresentable {
    let url: URL
    var isActive: Bool
    var isMuted: Bool
    var isPaused: Bool

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.setMuted(isMuted)
        view.setPlaying(isActive && !isPaused)
    }

    static func dismantleUIView(_ view: PlayerUIView, coordinator: ()) {
        view.teardown()
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    func configure(url: URL) {
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        playerLayer.player = queue
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    func setPlaying(_ playing: Bool) {
        guard let player else { return }
        if playing {
            if player.timeControlStatus != .playing { player.play() }
        } else {
            player.pause()
        }
    }

    func setMuted(_ muted: Bool) { player?.isMuted = muted }

    func teardown() {
        player?.pause()
        looper?.disableLooping()
        playerLayer.player = nil
        player = nil
        looper = nil
    }
}
