import SwiftUI

/// Profile, Earn, Connect, List. Each tab keeps its own navigation stack.
struct MainTabView: View {
    let model: AppModel
    let onReview: () -> Void

    var body: some View {
        TabView {
            Tab("Profile", systemImage: "person") {
                NavigationStack { ProfileView(model: model, onReview: onReview) }
            }
            Tab("Earn", systemImage: "gift") {
                NavigationStack { EarnView(store: model.earn) }
            }
            Tab("Connect", systemImage: "person.2") {
                NavigationStack { ConnectView(store: model.earn) }
            }
            Tab("List", systemImage: "bookmark") {
                NavigationStack { ListTabView(store: model.earn) }
            }
        }
        .tint(Theme.accent)
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
