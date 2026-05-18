import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var chatVM: ChatViewModel
    @State private var selectedTab: AppTab = .chat

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ChatView()
                    .environmentObject(chatVM)
                    .opacity(selectedTab == .chat ? 1 : 0)
                    .allowsHitTesting(selectedTab == .chat)

                ArticlesView()
                    .opacity(selectedTab == .read ? 1 : 0)
                    .allowsHitTesting(selectedTab == .read)

                FlashcardsView()
                    .opacity(selectedTab == .practice ? 1 : 0)
                    .allowsHitTesting(selectedTab == .practice)

                StudyView()
                    .opacity(selectedTab == .study ? 1 : 0)
                    .allowsHitTesting(selectedTab == .study)

                SettingsView()
                    .opacity(selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(selectedTab == .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AppTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
