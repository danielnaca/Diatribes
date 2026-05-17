import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("Chat", systemImage: "message") }

            FlashcardsView()
                .tabItem { Label("Flashcards", systemImage: "rectangle.on.rectangle") }

            ArticlesView()
                .tabItem { Label("Articles", systemImage: "newspaper") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
