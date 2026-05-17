import SwiftUI
import SwiftData

@main
struct DiatribesApp: App {
    @StateObject private var chatVM = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatVM)
        }
        .modelContainer(for: [Flashcard.self, SavedArticle.self, FeedSubscription.self])
    }
}
