import AVFoundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false

    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

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
        rec.delegate = self
        rec.record()
        recorder = rec
        outputURL = tmp
        isRecording = true
    }

    /// Stop recording and return the audio data.
    func stop() async -> Data? {
        recorder?.stop()
        recorder = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false)

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
