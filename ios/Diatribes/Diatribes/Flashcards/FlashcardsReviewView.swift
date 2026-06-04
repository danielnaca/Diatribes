import SwiftUI
import SwiftData

struct FlashcardsReviewView: View {
    let cards: [Flashcard]
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var revealed = false

    private var current: Flashcard? { cards.indices.contains(index) ? cards[index] : nil }
    private var progress: Double { cards.isEmpty ? 1 : Double(index) / Double(cards.count) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: progress)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Spacer()

                if let card = current {
                    cardFace(card)
                } else {
                    doneView
                }

                Spacer()

                if current != nil {
                    actionRow
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Card face

    private func cardFace(_ card: Flashcard) -> some View {
        VStack(spacing: 20) {
            Text(card.translation)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(posColor(card.pos))
                .multilineTextAlignment(.center)

            if revealed {
                Text(card.english)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                Button("Show answer") { withAnimation { revealed = true } }
                    .font(.body)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: Action row

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button {
                current?.reviewedHard()
                advance()
            } label: {
                Text("Hard")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                current?.reviewedEasy()
                advance()
            } label: {
                Text("Easy")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
        .opacity(revealed ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: revealed)
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 12) {
            Text("All done!")
                .font(.largeTitle.bold())
            Text("You reviewed \(cards.count) card\(cards.count == 1 ? "" : "s").")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
                .padding(.top, 8)
        }
    }

    // MARK: Helpers

    private func advance() {
        revealed = false
        index += 1
    }

}
