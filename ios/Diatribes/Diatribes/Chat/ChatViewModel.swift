import Combine
import Foundation
import SwiftUI

// MARK: - Settings types

enum CorrectionMode: String, CaseIterable, Identifiable {
    case off           = "off"
    case correct       = "correct"
    case correctAndRepeat = "repeat"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off:              return "Off"
        case .correct:          return "Correct"
        case .correctAndRepeat: return "Correct & repeat"
        }
    }
}

let supportedLanguages = ["French", "Spanish"]

// Google Neural2 voices then OpenAI voices — matches web Settings view
let googleVoices: [(key: String, label: String)] = [
    ("google-fr-a", "Google FR — female"),
    ("google-fr-b", "Google FR — male"),
    ("google-fr-c", "Google FR — female 2"),
    ("google-es-a", "Google ES — female"),
    ("google-es-b", "Google ES — male"),
]
let openAIVoices: [(key: String, label: String)] = [
    ("nova",    "Nova"),
    ("alloy",   "Alloy"),
    ("echo",    "Echo"),
    ("fable",   "Fable"),
    ("onyx",    "Onyx"),
    ("shimmer", "Shimmer"),
]

let posTags: [(key: String, label: String)] = [
    ("noun", "Nouns"),
    ("verb", "Verbs"),
    ("adj",  "Adjectives"),
    ("adv",  "Adverbs"),
]

// MARK: - ViewModel

@MainActor
final class ChatViewModel: ObservableObject {

    // Persisted settings
    @AppStorage("language")        var language       = "French"
    @AppStorage("voice")           var voice          = "google-fr-a"
    @AppStorage("correctionMode")  var correctionModeRaw = CorrectionMode.correct.rawValue
    @AppStorage("responseLength")  var responseLength = 1   // 1=Brief, 3=Medium, 5=Long
    @AppStorage("highlightsOn")    var highlightsOn   = true
    @AppStorage("speed")           var speed          = 1.0
    @AppStorage("enabledPOSRaw")   var enabledPOSRaw  = "noun,verb,adj,adv"

    var correctionMode: CorrectionMode {
        get { CorrectionMode(rawValue: correctionModeRaw) ?? .correct }
        set { correctionModeRaw = newValue.rawValue }
    }

    var enabledPOS: Set<String> {
        get { Set(enabledPOSRaw.split(separator: ",").map(String.init)) }
        set { enabledPOSRaw = newValue.sorted().joined(separator: ",") }
    }

    // Chat state
    @Published var messages: [ChatMessage] = []
    @Published var inputText       = ""
    @Published var isProcessing    = false
    @Published var isRecording     = false
    @Published var showChatOptions = false
    @Published var audioLevel: Float = 0.0

    private var history: [HistoryMessage] = []
    private var turnFromVoice = false
    private let recorder = AudioRecorder()
    private let player   = AudioPlayer()
    private var cancellables = Set<AnyCancellable>()

    init() {
        recorder.$audioLevel
            .assign(to: &$audioLevel)
    }

    // MARK: Send text

    func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }
        inputText = ""
        turnFromVoice = false
        Task { await process(userText: text) }
    }

    // MARK: Voice

    func toggleRecording() {
        if isRecording {
            Task { await stopAndTranscribe() }
        } else {
            isRecording   = true
            turnFromVoice = true
            recorder.start()
        }
    }

    private func stopAndTranscribe() async {
        isRecording = false
        guard let data = await recorder.stop() else { return }
        do {
            let text = try await APIClient.shared.transcribe(audioData: data)
            guard !text.isEmpty else { return }
            await process(userText: text)
        } catch {
            // silent failure — no status text in UI
        }
    }

    // MARK: Core processing

    private func process(userText: String) async {
        isProcessing = true
        messages.append(ChatMessage(role: .user, text: userText))

        do {
            let result = try await APIClient.shared.respond(
                userText: userText,
                history: history,
                systemPrompt: buildSystemPrompt()
            )

            if let correction = result.correction, !correction.isEmpty {
                messages.append(ChatMessage(role: .correction, text: correction))
            }

            let langCode = language == "Spanish" ? "es" : "fr"
            let swapped = DictSwap.shared.swap(
                text: result.response,
                langCode: langCode,
                enabledPOS: enabledPOS,
                highlightsOn: highlightsOn
            )

            messages.append(ChatMessage(
                role: .assistant,
                text: result.response,
                attributed: swapped.attributed
            ))

            history.append(HistoryMessage(role: "user",      content: userText))
            history.append(HistoryMessage(role: "assistant", content: result.response))

            if turnFromVoice {
                let audio = try await APIClient.shared.speak(
                    text: swapped.plain,
                    voice: voice,
                    language: language,
                    speakingRate: speed
                )
                await player.play(audio)
            }
        } catch {
            // silent failure
        }

        isProcessing = false
    }

    // MARK: System prompt — POS only, mirrors server.py

    private func buildSystemPrompt() -> String {
        let L = language

        let correctionBlock: String
        switch correctionMode {
        case .off:
            correctionBlock = "Do NOT correct the user. Set 'correction' to null and 'trouble_words' to null."
        case .correct, .correctAndRepeat:
            correctionBlock = """
            CORRECTION TASK: Check the user's message for any \(L) grammar, \
            vocabulary, or conjugation errors. If errors exist, provide the \
            corrected version of their FULL message in the 'correction' field. \
            If they spoke only English or their \(L) was correct, set 'correction' \
            to null. List specific \(L) words they misused in 'trouble_words'.
            """
        }

        let lengthRule: String
        switch responseLength {
        case 1:  lengthRule = "Keep responses very short — 1 sentence maximum."
        case 3:  lengthRule = "Use 3–4 sentences."
        case 5:  lengthRule = "Feel free to be expansive — go into detail, ask follow-ups, elaborate."
        default: lengthRule = "Keep responses brief — 2 sentences maximum."
        }

        let langRule = """
        OUTPUT LANGUAGE — THIS IS YOUR MOST IMPORTANT RULE: Write your response in English and English only. \
        You are strictly forbidden from using any \(L) words, phrases, or sentences in the 'response' field. \
        It does not matter what language the user writes in. Even if they write entirely in \(L), you must respond in English. \
        The \(L) word substitution is handled automatically by the app after you reply — you do not need to do it. \
        Your only job is to write natural, engaging English.
        """

        return """
        \(langRule)

        You are a friendly conversational partner helping someone practice \(L). Have genuine, interesting conversations — be curious and engaged.

        LENGTH: \(lengthRule)

        \(correctionBlock)

        Respond ONLY with valid JSON, no markdown fences:
        {"correction": "corrected full message or null", "response": "your reply", "trouble_words": ["words"] or null}

        REMINDER: Your 'response' must be in English only — no \(L) words whatsoever.
        """
    }
}
