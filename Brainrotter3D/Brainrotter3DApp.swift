import SwiftUI
import AVFAudio

/// Brainrotter3D — a fully self-contained Apple Vision Pro app for watching Instagram
/// Reels. Login, 2FA, and the feed all run natively on-device against `i.instagram.com`
/// (ported from the reverse-engineered iOS client). No companion server.
@main
struct Brainrotter3DApp: App {
    init() {
        // Let reel audio play through the headset.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Portrait window — reels are 9:16, so a tall frame fills with one reel.
        .defaultSize(width: 520, height: 920)
        .windowResizability(.contentSize)
    }
}
