import SwiftUI
import SwiftData

struct FeedsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FeedSubscription.addedAt, order: .forward) private var feeds: [FeedSubscription]

    @State private var level: FeedsLevel = .subscriptions
    @State private var selectedFeed: FeedSubscription?
    @State private var feedItems: [FeedItem] = []
    @State private var urlText     = ""
    @State private var isLoading   = false
    @State private var isAdding    = false
    @State private var errorMsg: String?
    @State private var readerArticle: ArticleReaderData?

    enum FeedsLevel { case subscriptions, articles }

    var body: some View {
        VStack(spacing: 0) {
            if level == .subscriptions {
                addBar
                Divider()
            }
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if level == .subscriptions {
                subscriptionList
            } else {
                articleList
            }
        }
        .navigationDestination(item: $readerArticle) { data in
            ArticleReaderView(title: data.title, source: data.source, paragraphs: data.paragraphs)
        }
    }

    // MARK: Add bar

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField("Paste RSS feed URL…", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await addFeed() } }

            Button {
                Task { await addFeed() }
            } label: {
                if isAdding {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Subscription list

    private var subscriptionList: some View {
        List {
            if let msg = errorMsg {
                Text(msg).font(.caption).foregroundStyle(.red).listRowSeparator(.hidden)
            }
            // All row
            Button {
                Task { await loadAllFeeds() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tray.2")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                    Text("All")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            ForEach(feeds) { feed in
                Button {
                    Task { await loadFeed(feed) }
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: feed.favicon)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Image(systemName: "newspaper")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text(feed.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteFeeds)

            if feeds.isEmpty {
                Text("Paste an RSS feed URL above to subscribe.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    // MARK: Article list

    private var articleList: some View {
        List {
            // Back row
            Button {
                withAnimation { level = .subscriptions }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                    Text(selectedFeed?.title ?? "All")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)

            if let msg = errorMsg {
                Text(msg).font(.caption).foregroundStyle(.red).listRowSeparator(.hidden)
            }

            ForEach(feedItems) { item in
                Button {
                    Task { await openItem(item) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if !item.excerpt.isEmpty {
                            Text(item.excerpt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(item.date)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            if feedItems.isEmpty && errorMsg == nil {
                Text("No articles found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    // MARK: Actions

    private func addFeed() async {
        let raw = urlText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        isAdding = true
        errorMsg = nil
        defer { isAdding = false }

        do {
            let fetched = try await APIClient.shared.fetchFeed(urlString: raw)
            let sub = FeedSubscription(
                title:   fetched.title,
                feedUrl: raw,
                siteUrl: fetched.site_url,
                favicon: fetched.favicon
            )
            modelContext.insert(sub)
            urlText = ""
        } catch {
            errorMsg = "Couldn't add feed: \(error.localizedDescription)"
        }
    }

    private func loadFeed(_ feed: FeedSubscription) async {
        isLoading    = true
        errorMsg     = nil
        selectedFeed = feed
        feedItems    = []
        defer { isLoading = false }

        do {
            let fetched = try await APIClient.shared.fetchFeed(urlString: feed.feedUrl)
            feedItems = fetched.items
            withAnimation { level = .articles }
        } catch {
            errorMsg = "Couldn't load feed: \(error.localizedDescription)"
        }
    }

    private func loadAllFeeds() async {
        isLoading    = true
        errorMsg     = nil
        selectedFeed = nil
        feedItems    = []
        defer { isLoading = false }

        var all: [FeedItem] = []
        for feed in feeds {
            if let fetched = try? await APIClient.shared.fetchFeed(urlString: feed.feedUrl) {
                all.append(contentsOf: fetched.items)
            }
        }
        feedItems = all
        withAnimation { level = .articles }
    }

    private func openItem(_ item: FeedItem) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await APIClient.shared.fetchArticle(urlString: item.url)
            readerArticle = ArticleReaderData(title: fetched.title, source: fetched.url, paragraphs: fetched.paragraphs)
        } catch {
            errorMsg = "Couldn't load article."
        }
    }

    private func deleteFeeds(at offsets: IndexSet) {
        for i in offsets { modelContext.delete(feeds[i]) }
    }
}
