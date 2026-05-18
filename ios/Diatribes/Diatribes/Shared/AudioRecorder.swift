import AVFoundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0

    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var meterTimer: Timer?

    func start() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default)
        try? session.setActive(true)
        #endif

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        guard let rec = try? AVAudioRecorder(url: tmp, settings: settings) else { return }
        rec.isMeteringEnabled = true
        rec.delegate = self
        rec.record()
        recorder = rec
        outputURL = tmp
        isRecording = true

        // Poll metering at 50ms — maps dBFS -60…0 to 0…1
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = self.recorder else { return }
                rec.updateMeters()
                let db = rec.averagePower(forChannel: 0)
                self.audioLevel = max(0, min(1, (db + 60) / 60))
            }
        }
    }

    func stop() async -> Data? {
        meterTimer?.invalidate()
        meterTimer = nil
        audioLevel = 0.0

        recorder?.stop()
        recorder = nil
        isRecording = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif

        guard let url = outputURL,
              let data = try? Data(contentsOf: url)
        else { return nil }

        try? FileManager.default.removeItem(at: url)
        outputURL = nil
        return data
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {}
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let e = error { print("AudioRecorder encode error: \(e)") }
    }
}
