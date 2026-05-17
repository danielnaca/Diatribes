import SwiftUI

struct ArticlesView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                Divider()
                TabView(selection: $selectedTab) {
                    SavedArticlesView()
                        .tag(0)
                    FeedsView()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Articles")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Saved", tag: 0)
            tabButton(title: "Feeds", tag: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func tabButton(title: String, tag: Int) -> some View {
        Button {
            withAnimation { selectedTab = tag }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selectedTab == tag ? Color(.systemGray5) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tag ? .primary : .secondary)
    }
}
