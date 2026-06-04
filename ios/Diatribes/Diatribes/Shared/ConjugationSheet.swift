import SwiftUI

struct ConjugationSheet: View {
    let verb: String        // the foreign-language verb (e.g. "parler")
    let english: String     // English meaning (e.g. "to speak")
    let language: String    // "French" or "Spanish"

    @Environment(\.dismiss) private var dismiss
    @State private var result: ConjugationResult?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    loadingView
                } else if failed {
                    failureView
                } else if let result {
                    conjugationTable(result)
                }
            }
            .navigationTitle(verb)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Color.brandParchment)
        .task { await load() }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Conjugating…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Couldn't load conjugation")
                .font(.headline)
            Button("Try again") { Task { await load() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Table

    private func conjugationTable(_ result: ConjugationResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header info
                HStack(spacing: 8) {
                    Text(english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if result.irregular {
                        Text("irregular")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)

                // Tenses
                ForEach(result.tenses, id: \.name) { tense in
                    tenseBlock(tense)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private func tenseBlock(_ tense: ConjugationTense) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tense.name)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(tense.forms.enumerated()), id: \.offset) { index, form in
                    HStack {
                        Text(form.pronoun)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)
                        Text(form.form)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(index % 2 == 0 ? Color.clear : Color(.systemGray6))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
        }
    }

    // MARK: Load

    private func load() async {
        loading = true
        failed = false
        do {
            result = try await APIClient.shared.conjugate(verb: verb, language: language)
        } catch {
            failed = true
        }
        loading = false
    }
}
