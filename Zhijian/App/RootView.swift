import SwiftUI

struct RootView: View {
    @StateObject private var env = AppEnvironment.shared
    @State private var tab: Int = RootView.initialTab
    @State private var paletteID = ZJPaletteStore.currentID
    @Environment(\.scenePhase) private var scenePhase
    @State private var appIconApplied = false

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
            StatsView()
                .transition(.opacity)
                .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(1)
            SettingsView()
                .transition(.opacity)
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
        }
        .environmentObject(env)
        .tint(ZJ.accent)
        .preferredColorScheme(ZJPaletteStore.appearanceMode == .dark ? .dark
            : (ZJPaletteStore.appearanceMode == .light ? .light : nil))
        .id(paletteID)
        .animation(.easeInOut(duration: 0.28), value: paletteID)
        .animation(.easeInOut(duration: 0.22), value: tab)
        .onReceive(NotificationCenter.default.publisher(for: .zjPaletteChanged)) { _ in
            paletteID = ZJPaletteStore.currentID
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if UserDefaults.standard.object(forKey: "appIcon.followPalette") == nil {
                    UserDefaults.standard.set(true, forKey: "appIcon.followPalette")
                }
                let enabled = UserDefaults.standard.bool(forKey: "appIcon.followPalette")
                if !appIconApplied {
                    appIconApplied = true
                    AppIconController.apply(paletteID: ZJPaletteStore.currentID, enabled: enabled)
                }
                _ = enabled
                // P2-01：daily / weekly 周期到达时补跑自动备份
                if AutoBackupStore.shared.shouldRunNow() {
                    let backup = AppEnvironment.shared.backup
                    Task {
                        let result = await AutoBackupRunner.runNow(backup: backup)
                        NSLog("[AutoBackup] %@", result)
                    }
                }
            case .background:
                // P2-01：退出 App 时自动备份
                if AutoBackupStore.shared.frequency == .onExit {
                    let backup = AppEnvironment.shared.backup
                    Task {
                        let result = await AutoBackupRunner.runNow(backup: backup)
                        NSLog("[AutoBackup] %@", result)
                    }
                }
            default:
                break
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
