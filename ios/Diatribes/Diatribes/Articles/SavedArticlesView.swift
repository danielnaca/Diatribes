import SwiftUI
import SwiftData

struct SavedArticlesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedArticle.savedAt, order: .reverse) private var articles: [SavedArticle]
    @AppStorage("language") private var language = "French"

    @State private var urlText   = ""
    @State private var isLoading = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 0) {
            addBar
            Divider()
            if articles.isEmpty {
                emptyState
            } else {
                articleList
            }
        }
    }

    // MARK: Add bar

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField("Paste article URL…", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await addArticle() } }

            Button {
                Task { await addArticle() }
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Article list

    private var articleList: some View {
        List {
            if let msg = errorMsg {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .listRowSeparator(.hidden)
            }
            ForEach(articles) { article in
                NavigationLink {
                    ArticleReaderView(
                        title: article.title,
                        source: article.url,
                        paragraphs: article.paragraphs
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(article.excerpt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(hostName(from: article.url))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: deleteArticles)
        }
        .listStyle(.plain)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            if let msg = errorMsg {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text("No saved articles")
                    .font(.headline)
                Text("Paste a URL above to save an article for reading.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    // MARK: Actions

    private func addArticle() async {
        let raw = urlText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        isLoading = true
        errorMsg  = nil
        defer { isLoading = false }

        do {
            let fetched = try await APIClient.shared.fetchArticle(urlString: raw)
            let article = SavedArticle(
                title:      fetched.title,
                url:        fetched.url,
                excerpt:    fetched.excerpt,
                paragraphs: fetched.paragraphs,
                language:   language
            )
            modelContext.insert(article)
            urlText = ""
        } catch {
            errorMsg = "Couldn't fetch article: \(error.localizedDescription)"
        }
    }

    private func deleteArticles(at offsets: IndexSet) {
        for i in offsets { modelContext.delete(articles[i]) }
    }

    private func hostName(from urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }
}
