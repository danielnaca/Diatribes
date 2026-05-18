import SwiftUI

struct StudyView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming Soon",
                systemImage: "books.vertical",
                description: Text("Study features are on the way.")
            )
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
