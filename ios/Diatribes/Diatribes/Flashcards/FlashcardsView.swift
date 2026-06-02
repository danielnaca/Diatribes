import SwiftUI
import SwiftData

struct FlashcardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Flashcard.createdAt, order: .reverse) private var allCards: [Flashcard]
    @AppStorage("language") private var language = "French"

    @State private var filterPOS: Set<String> = ["noun", "verb", "adj", "adv"]
    @State private var showingReview  = false

    private var filtered: [Flashcard] {
        allCards.filter { $0.language == language && filterPOS.contains($0.pos) }
    }

    private var dueCards: [Flashcard] {
        filtered.filter { $0.dueAt <= Date() }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                posFilterBar
                if filtered.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }
            .navigationTitle("Flashcards")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !dueCards.isEmpty {
                        Button("Review \(dueCards.count)") {
                            showingReview = true
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingReview) {
                AudioReviewView(cards: dueCards, language: language)
            }
        }
    }

    // MARK: POS filter

    private var posFilterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(posTags, id: \.key) { tag in
                        let isOn = filterPOS.contains(tag.key)
                        Button {
                            if isOn { filterPOS.remove(tag.key) }
                            else     { filterPOS.insert(tag.key) }
                        } label: {
                            Text(tag.label)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isOn ? posColor(tag.key) : Color(.systemGray5))
                                .foregroundStyle(isOn ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(.systemBackground))
            Divider()
        }
    }

    // MARK: Card list

    private var cardList: some View {
        List {
            ForEach(filtered) { card in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.translation)
                            .font(.body.weight(.medium))
                            .foregroundStyle(posColor(card.pos))
                        Text(card.english)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if card.dueAt <= Date() {
                        Text("Due")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .onDelete(perform: deleteCards)
        }
        .listStyle(.plain)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No flashcards yet")
                .font(.headline)
            Text("Tap words in the chat to save them here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: Delete

    private func deleteCards(at offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(filtered[i])
        }
    }

    // MARK: Helpers

    private func posColor(_ pos: String) -> Color {
        switch pos {
        case "noun": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "verb": return Color(red: 0.086, green: 0.639, blue: 0.239)
        case "adj":  return Color(red: 0.761, green: 0.255, blue: 0.047)
        case "adv":  return Color(red: 0.486, green: 0.231, blue: 0.929)
        default:     return .gray
        }
    }
}
