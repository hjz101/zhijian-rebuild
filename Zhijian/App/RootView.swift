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
        ZStack {
            TabView(selection: $tab) {
                ShelfView().tag(0)
                StatsView().tag(1)
                SettingsView().tag(2)
            }
            .toolbar(.hidden, for: .tabBar)

            // 悬浮玻璃 Tab 栏（Liquid Glass 纪律：玻璃只包 chrome，暗边是灵魂）
            VStack {
                Spacer()
                glassTabBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
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
                if AutoBackupStore.shared.shouldRunNow() {
                    let backup = AppEnvironment.shared.backup
                    Task {
                        let result = await AutoBackupRunner.runNow(backup: backup)
                        NSLog("[AutoBackup] %@", result)
                    }
                }
            case .background:
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
    }

    // MARK: - 悬浮玻璃 Tab 栏

    private var glassTabBar: some View {
        HStack(spacing: 4) {
            glassTabItem(index: 0, icon: "books.vertical", label: "书架")
            glassTabItem(index: 1, icon: "chart.bar.xaxis", label: "统计")
            glassTabItem(index: 2, icon: "gearshape", label: "设置")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .liquidGlass(cornerRadius: 26)
        .shadow(color: Color.black.opacity(ZJPaletteStore.current.isDark ? 0.45 : 0.15), radius: 20, y: 8)
    }

    private func glassTabItem(index: Int, icon: String, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { tab = index }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: tab == index ? .semibold : .regular))
                    .foregroundStyle(tab == index ? ZJ.accent : ZJ.textSecondary)
                    .frame(height: 22)
                Text(label)
                    .font(.system(size: 9, weight: tab == index ? .semibold : .regular))
                    .foregroundStyle(tab == index ? ZJ.accent : ZJ.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
