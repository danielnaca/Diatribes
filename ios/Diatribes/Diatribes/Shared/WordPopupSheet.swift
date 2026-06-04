import SwiftUI
import SwiftData

struct WordTapInfo: Identifiable {
    let id       = UUID()
    let english:     String
    let translation: String
    let pos:         String
    let language:    String   // "fr" or "es"
}

struct WordPopupSheet: View {
    let info: WordTapInfo
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @AppStorage("language")      private var language = "French"

    @State private var saved = false
    @State private var showConjugation = false

    private var fullLanguage: String {
        info.language == "es" ? "Spanish" : "French"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // Word display
            VStack(spacing: 8) {
                Text(info.translation)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(posColor(info.pos))
                Text(info.english)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                posBadge
            }
            .padding(.bottom, 28)

            VStack(spacing: 10) {
                // Save button
                Button {
                    saveFlashcard()
                } label: {
                    Label(saved ? "Saved to flashcards" : "Add to flashcards",
                          systemImage: saved ? "checkmark" : "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(saved ? Color.green : posColor(info.pos))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(saved)

                // Conjugation button — verbs only
                if info.pos == "verb" {
                    Button {
                        showConjugation = true
                    } label: {
                        Label("See conjugation", systemImage: "tablecells")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray6))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .presentationDetents(info.pos == "verb" ? [.height(320)] : [.height(260)])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showConjugation) {
            ConjugationSheet(
                verb: info.translation,
                english: "to \(info.english)",
                language: fullLanguage
            )
        }
    }

    private var posBadge: some View {
        return Text(posLabel(info.pos))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(posColor(info.pos).opacity(0.15))
            .foregroundStyle(posColor(info.pos))
            .clipShape(Capsule())
    }

    private func saveFlashcard() {
        let fullLanguage = info.language == "es" ? "Spanish" : "French"
        let card = Flashcard(
            english:     info.english,
            translation: info.translation,
            pos:         info.pos,
            language:    fullLanguage
        )
        modelContext.insert(card)
        withAnimation { saved = true }
    }

}
