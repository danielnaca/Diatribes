import SwiftUI

struct SettingsView: View {
    @AppStorage("language") private var language = "French"
    @AppStorage("voice")    private var voice    = "google-fr-a"

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                voiceSection
                howItWorksSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: Language

    private var languageSection: some View {
        Section("Language") {
            Picker("Language", selection: $language) {
                ForEach(supportedLanguages, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            .onChange(of: language) { resetVoiceForLanguage() }
        }
    }

    // MARK: Voice

    private var voiceSection: some View {
        Section("Voice") {
            let googleFiltered = googleVoices.filter { isVoiceForLanguage($0.key) }
            if !googleFiltered.isEmpty {
                voiceGroup(header: "Google Neural2", voices: googleFiltered)
            }
            voiceGroup(header: "OpenAI", voices: openAIVoices)
        }
    }

    @ViewBuilder
    private func voiceGroup(header: String, voices: [(key: String, label: String)]) -> some View {
        Section(header: Text(header).font(.caption).textCase(.uppercase)) {
            ForEach(voices, id: \.key) { item in
                HStack {
                    Text(item.label)
                    Spacer()
                    if voice == item.key {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { voice = item.key }
            }
        }
    }

    // MARK: How it works

    private var howItWorksSection: some View {
        Section("How it works") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Diatribes helps you learn languages through conversation.")
                    .font(.body)
                Text("You chat in any language. Claude always replies in English, then the app automatically swaps English words for their translation in your target language — color-coded by part of speech.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Record your voice with the mic button, or type and send. Use the options slider in the chat to control which word types get swapped, answer length, and correction behavior.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Helpers

    private func isVoiceForLanguage(_ key: String) -> Bool {
        let prefix = language == "Spanish" ? "google-es" : "google-fr"
        return key.hasPrefix(prefix)
    }

    private func resetVoiceForLanguage() {
        let defaultVoice = language == "Spanish" ? "google-es-a" : "google-fr-a"
        if !isVoiceForLanguage(voice) {
            voice = defaultVoice
        }
    }
}
