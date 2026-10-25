import SwiftUI

struct RootView: View {
    @StateObject private var env = AppEnvironment.shared
    @State private var tab: Int = RootView.initialTab
    @State private var paletteID = ZJPaletteStore.currentID

    private static var initialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        for arg in args {
            if arg.hasPrefix("-tab="), let v = Int(arg.dropFirst(5)), (0...2).contains(v) { return v }
        }
        return 0
    }

    var body: some View {
        TabView(selection: $tab) {
            ShelfView()
                .transition(.opacity)
                .tabItem { Label("书架", systemImage: "books.vertical") }.tag(0)
            StatsView().tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(1)
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
        }
        .environmentObject(env)
        .tint(ZJ.accent)
        .preferredColorScheme(ZJPaletteStore.current.isDark ? .dark : .light)
        .id(paletteID)
        .animation(.easeInOut(duration: 0.28), value: paletteID)
        .onReceive(NotificationCenter.default.publisher(for: .zjPaletteChanged)) { _ in
            paletteID = ZJPaletteStore.currentID
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
