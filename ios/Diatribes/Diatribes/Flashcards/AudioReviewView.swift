import AVFoundation
import Combine
import SwiftUI

// MARK: - ViewModel

@MainActor
final class AudioReviewViewModel: NSObject, ObservableObject {

    enum State {
        case speaking          // TTS reading the foreign word
        case ready             // waiting for user to tap mic
        case recording         // user is speaking
        case evaluating        // transcribing
        case correct(String)   // right! + english word
        case wrong(String)     // wrong + correct english
        case done
    }

    let cards: [Flashcard]
    let language: String

    @Published var state: State = .speaking
    @Published var currentIndex = 0
    @Published var correctCount = 0
    @Published var audioLevel: Float = 0

    private let synth = AVSpeechSynthesizer()
    private let recorder = AudioRecorder()
    private var cancellables = Set<AnyCancellable>()
    private var onSpeakDone: (() -> Void)?

    var current: Flashcard? { cards.indices.contains(currentIndex) ? cards[currentIndex] : nil }
    var progress: Double { cards.isEmpty ? 1 : Double(currentIndex) / Double(cards.count) }

    init(cards: [Flashcard], language: String) {
        self.cards = cards
        self.language = language
        super.init()
        synth.delegate = self
        recorder.$audioLevel.assign(to: &$audioLevel)
    }

    // MARK: Public

    func begin() {
        guard let card = current else { return }
        readForeignWord(card.translation)
    }

    func replayWord() {
        guard let card = current, case .ready = state else { return }
        readForeignWord(card.translation)
    }

    func toggleMic() {
        switch state {
        case .ready:
            state = .recording
            recorder.start()
        case .recording:
            submitAnswer()
        default:
            break
        }
    }

    // MARK: TTS

    private func readForeignWord(_ word: String) {
        state = .speaking
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: language == "Spanish" ? "es-ES" : "fr-FR")
        utterance.rate = 0.38
        utterance.preUtteranceDelay = 0.15
        onSpeakDone = { [weak self] in self?.state = .ready }
        synth.speak(utterance)
    }

    private func sayFeedback(_ text: String, then next: @escaping () -> Void) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        onSpeakDone = next
        synth.speak(utterance)
    }

    // MARK: Answer evaluation

    private func submitAnswer() {
        state = .evaluating
        Task {
            guard let data = await recorder.stop(), let card = current else {
                advance(); return
            }
            do {
                let raw = try await APIClient.shared.transcribe(audioData: data)
                let heard = normalize(raw)
                let expected = normalize(card.english)
                let correct = isMatch(heard, expected)

                if correct {
                    correctCount += 1
                    card.reviewedEasy()
                    state = .correct(card.english)
                    sayFeedback("Correct!") { self.advance() }
                } else {
                    card.reviewedHard()
                    state = .wrong(card.english)
                    sayFeedback("Wrong — it's \(card.english).") { self.advance() }
                }
            } catch {
                advance()
            }
        }
    }

    private func advance() {
        if currentIndex + 1 < cards.count {
            currentIndex += 1
            guard let next = current else { return }
            readForeignWord(next.translation)
        } else {
            state = .done
        }
    }

    // MARK: Match logic

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"^to\s+"#, with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }

    private func isMatch(_ heard: String, _ expected: String) -> Bool {
        if heard == expected { return true }
        if heard.contains(expected) || expected.contains(heard) { return true }
        // Word overlap
        let heardWords = Set(heard.split(separator: " ").map(String.init))
        let expWords   = Set(expected.split(separator: " ").map(String.init))
        guard !heardWords.isEmpty, !expWords.isEmpty else { return false }
        let overlap = Double(heardWords.intersection(expWords).count)
        return overlap / Double(max(heardWords.count, expWords.count)) >= 0.75
    }
}

extension AudioReviewViewModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            onSpeakDone?()
            onSpeakDone = nil
        }
    }
}

// MARK: - View

struct AudioReviewView: View {
    @StateObject private var vm: AudioReviewViewModel
    @Environment(\.dismiss) private var dismiss


    init(cards: [Flashcard], language: String) {
        _vm = StateObject(wrappedValue: AudioReviewViewModel(cards: cards, language: language))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                Spacer()
                cardContent
                Spacer()
                bottomControls
            }
            .navigationTitle("Audio Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Color.brandParchment)
        .task { vm.begin() }
    }

    // MARK: Progress

    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: vm.progress)
                .tint(Color.brandSand)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Text("\(vm.currentIndex + 1) of \(vm.cards.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Card content

    @ViewBuilder
    private var cardContent: some View {
        if case .done = vm.state {
            doneView
        } else if let card = vm.current {
            wordCard(card)
        }
    }

    private func wordCard(_ card: Flashcard) -> some View {
        VStack(spacing: 20) {
            // POS badge
            Text(posLabel(card.pos))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(posColor(card.pos).opacity(0.12))
                .foregroundStyle(posColor(card.pos))
                .clipShape(Capsule())

            // Foreign word — tap to replay
            Button {
                vm.replayWord()
            } label: {
                Text(card.translation)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(posColor(card.pos))
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)
            .disabled(!canReplay)

            // Status
            stateLabel(card)
        }
        .padding(.horizontal, 32)
        .animation(.easeInOut(duration: 0.2), value: stateKey)
    }

    @ViewBuilder
    private func stateLabel(_ card: Flashcard) -> some View {
        switch vm.state {
        case .speaking:
            Label("Listening…", systemImage: "speaker.wave.2.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .ready:
            Text("Tap the mic and say it in English")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .recording:
            WaveformView(level: vm.audioLevel)
                .frame(height: 28)
                .frame(maxWidth: 200)
        case .evaluating:
            ProgressView()
                .scaleEffect(0.9)
        case .correct(let english):
            VStack(spacing: 6) {
                Label("Correct!", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.086, green: 0.639, blue: 0.239))
                Text(english)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        case .wrong(let english):
            VStack(spacing: 6) {
                Label("Wrong", systemImage: "xmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)
                Text("It's: \(english)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        case .done:
            EmptyView()
        }
    }

    // MARK: Mic button

    private var bottomControls: some View {
        VStack(spacing: 8) {
            micButton
            if canReplay, case .ready = vm.state {
                Button("Replay word") { vm.replayWord() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 48)
    }

    private var micButton: some View {
        Button {
            vm.toggleMic()
        } label: {
            ZStack {
                Circle()
                    .fill(micBg)
                    .frame(width: 72, height: 72)
                micIcon
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .disabled(!micEnabled)
        .animation(.easeInOut(duration: 0.15), value: stateKey)
    }

    private var micBg: Color {
        switch vm.state {
        case .recording: return .red
        case .correct:   return Color(red: 0.086, green: 0.639, blue: 0.239)
        case .wrong:     return .red
        case .done:      return .clear
        default:         return Color.primary
        }
    }

    private var micIcon: Image {
        switch vm.state {
        case .speaking, .evaluating: return Image(systemName: "ellipsis")
        case .ready:                 return Image(systemName: "mic.fill")
        case .recording:             return Image(systemName: "stop.fill")
        case .correct:               return Image(systemName: "checkmark")
        case .wrong:                 return Image(systemName: "xmark")
        case .done:                  return Image(systemName: "checkmark")
        }
    }

    private var micEnabled: Bool {
        switch vm.state {
        case .ready, .recording: return true
        default: return false
        }
    }

    private var canReplay: Bool {
        if case .ready = vm.state { return true }
        return false
    }

    // stateKey for animations (equatable proxy)
    private var stateKey: Int {
        switch vm.state {
        case .speaking: return 0
        case .ready: return 1
        case .recording: return 2
        case .evaluating: return 3
        case .correct: return 4
        case .wrong: return 5
        case .done: return 6
        }
    }

    // MARK: Done screen

    private var doneView: some View {
        VStack(spacing: 20) {
            Text(scoreEmoji)
                .font(.system(size: 60))
            Text("\(vm.correctCount) / \(vm.cards.count)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
            Text(scoreMessage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private var scoreEmoji: String {
        let n = vm.cards.count
        switch vm.correctCount {
        case n:               return "🏆"
        case let c where c >= n * 4 / 5: return "🎉"
        case let c where c >= n / 2:     return "💪"
        default:              return "📚"
        }
    }

    private var scoreMessage: String {
        let n = vm.cards.count
        switch vm.correctCount {
        case n:               return "Perfect!"
        case let c where c >= n * 4 / 5: return "Really strong"
        case let c where c >= n / 2:     return "Keep going"
        default:              return "More practice needed"
        }
    }

}
