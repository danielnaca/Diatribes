import SwiftUI

enum AppTab: Int, CaseIterable {
    case chat, read, practice, study, settings

    var label: String {
        switch self {
        case .chat:     return "Chat"
        case .read:     return "Read"
        case .practice: return "Practice"
        case .study:    return "Study"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .chat:     return "mic"
        case .read:     return "newspaper"
        case .practice: return "brain"
        case .study:    return "books.vertical"
        case .settings: return "gearshape"
        }
    }
}

struct AppTabBar: View {
    @Binding var selectedTab: AppTab

    private let active   = Color(red: 188/255, green: 130/255, blue: 0)
    private let inactive = Color(red: 108/255, green: 108/255, blue: 108/255)
    private let border   = Color(red: 237/255, green: 237/255, blue: 237/255)

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(border)
                .frame(height: 0.5)
            HStack(spacing: 20) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    tabButton(tab)
                }
            }
            .padding(.top, 7)
            .padding(.bottom, 30)
        }
        .background(Color.white)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 21, weight: .regular))
                Text(tab.label)
                    .font(.system(size: 10, weight: .regular))
            }
            .frame(width: 60)
            .foregroundStyle(selectedTab == tab ? active : inactive)
        }
        .buttonStyle(.plain)
    }
}
