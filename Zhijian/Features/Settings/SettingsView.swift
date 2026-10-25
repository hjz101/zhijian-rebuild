import SwiftUI

struct SettingsView: View {
    enum Route: Hashable { case tts, backup, cookies, cloud }
    @EnvironmentObject private var env: AppEnvironment
    @State private var path: [Route] = []

    private var s: Binding<ReadingSettings> {
        Binding(get: { env.settings.settings }, set: { env.settings.settings = $0 })
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: Route.tts) { Label("朗读与 TTS", systemImage: "speaker.wave.2") }
                    NavigationLink(value: Route.backup) { Label("备份与同步", systemImage: "externaldrive.badge.icloud") }
                    NavigationLink(value: Route.cookies) { Label("Cookie 管理", systemImage: "network") }
                    NavigationLink(value: Route.cloud) { Label("iCloud 同步", systemImage: "icloud") }
                }

                Section("阅读") {
                    Picker("主题", selection: s.theme) {
                        ForEach(ReaderTheme.allCases) { t in Text(t.name).tag(t) }
                    }
                    Picker("字体", selection: s.fontFamily) {
                        ForEach(ReaderFontFamily.allCases) { f in Text(f.name).tag(f) }
                    }
                    Stepper("字号 \(Int(s.wrappedValue.fontSize))", value: s.fontSize, in: 14...32, step: 1)
                    Stepper("行距 \(Int(s.wrappedValue.lineHeight))", value: s.lineHeight, in: 0...24, step: 1)
                    Picker("翻页", selection: s.pageMode) {
                        Text("分页").tag(ReadingSettings.PageMode.paged)
                        Text("滚动").tag(ReadingSettings.PageMode.scroll)
                    }
                    Toggle("显示页码", isOn: s.showPageNumber)
                }

                Section("数据") {
                    Text("书架 \(env.books.books.count) 本 · 书源 \(env.sources.sources.count) 个")
                    Text("本地书 \(LocalLibrary.shared.books.count) 本")
                }

                Section {
                    HStack {
                        Text("版本"); Spacer(); Text("2.0 (1)").foregroundStyle(.secondary)
                    }
                    Text("指尖阅读 2.0 · 基于 QiReader 逆向的重建工程").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("我的")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .tts: TTSConfigView()
                case .backup: BackupView()
                case .cookies: CookieManageView()
                case .cloud: CloudSyncView()
                }
            }
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-autoOpenTTSConfig") { path = [.tts] }
                if args.contains("-autoOpenBackup") { path = [.backup] }
                if args.contains("-autoOpenCookies") { path = [.cookies] }
                if args.contains("-autoOpenCloud") { path = [.cloud] }
            }
        }
    }
}
