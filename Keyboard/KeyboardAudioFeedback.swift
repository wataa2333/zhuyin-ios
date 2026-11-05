import AVFAudio
import Foundation

/// Audio-session setup and sample decoding must never block keyboard touches or scrolling.
final class KeyboardAudioFeedback: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.wataa2333.zhuyin.audio", qos: .utility)
    private var players: [Bool: AVAudioPlayer] = [:]
    private var attemptedSetup = false

    func prepare() { queue.async { self.preparePlayers() } }

    func play(volume: UInt8, deleting: Bool) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        queue.async {
            self.preparePlayers()
            // Drop stale feedback if audio initialization was slow, rather than playing a backlog.
            guard ProcessInfo.processInfo.systemUptime - requestedAt < 0.12,
                  let player = self.players[deleting] else { return }
            player.volume = Float(volume) / 100
            player.currentTime = 0
            player.play()
        }
    }

    func stop() { queue.async { self.players.values.forEach { $0.stop() } } }

    private func preparePlayers() {
        guard !attemptedSetup else { return }
        attemptedSetup = true
        do { try AVAudioSession.sharedInstance().setCategory(.ambient) } catch { return }
        let bundle = Bundle(for: KeyboardAudioFeedback.self)
        for (deleting, name) in [(false, "tap"), (true, "delete")] {
            guard let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "KeySounds"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[deleting] = player
        }
    }
}
