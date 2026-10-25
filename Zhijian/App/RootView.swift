import SwiftUI

struct RootView: View {
    @StateObject private var env = AppEnvironment.shared
    @State private var tab: Int = RootView.initialTab

    private static var initialTab: Int {
        for arg in ProcessInfo.processInfo.arguments {
            if arg.hasPrefix("-tab="), let v = Int(arg.dropFirst(5)) { return v }
        }
        return 0
    }

    var body: some View {
        TabView(selection: $tab) {
            ShelfView().tabItem { Label("书架", systemImage: "books.vertical") }.tag(0)
            SourcesView().tabItem { Label("书源", systemImage: "antenna.radiowaves.left.and.right") }.tag(1)
            ExploreView().tabItem { Label("发现", systemImage: "square.grid.2x2") }.tag(3)
            SettingsView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
        }
        .environmentObject(env)
        .tint(ZJ.accent)
    }
}
