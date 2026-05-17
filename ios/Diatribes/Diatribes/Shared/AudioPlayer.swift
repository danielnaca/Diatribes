import AVFoundation

final class AudioPlayer: NSObject {
    private var player: AVAudioPlayer?

    /// Play raw audio bytes and await completion.
    func play(_ data: Data) async {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        guard let p = try? AVAudioPlayer(data: data) else { return }
        p.delegate = self
        player = p

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            objc_setAssociatedObject(p, &AssociatedKeys.continuation, ContinuationBox(continuation), .OBJC_ASSOCIATION_RETAIN)
            p.play()
        }

        try? session.setActive(false)
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        resume(player: player)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        resume(player: player)
    }

    private func resume(player: AVAudioPlayer) {
        guard let box = objc_getAssociatedObject(player, &AssociatedKeys.continuation) as? ContinuationBox else { return }
        box.continuation.resume()
        objc_setAssociatedObject(player, &AssociatedKeys.continuation, nil, .OBJC_ASSOCIATION_RETAIN)
    }
}

private enum AssociatedKeys {
    static var continuation: UInt8 = 0
}

private final class ContinuationBox {
    let continuation: CheckedContinuation<Void, Never>
    init(_ c: CheckedContinuation<Void, Never>) { continuation = c }
}
