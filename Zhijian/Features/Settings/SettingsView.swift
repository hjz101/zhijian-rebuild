// SettingsView.swift — 栖阅式「设置」页（浅色玻璃 + 分组卡片）
import SwiftUI

struct SettingsView: View {
    enum Route: Hashable { case tts, backup, cookies, cloud, replaceRules }
    @EnvironmentObject private var env: AppEnvironment
    @State private var path: [Route] = []
    @State private var showReaderSettings = false
    @State private var showSources = false
    @State private var placeholder: String?
    @State private var showAppearance = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("设置")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(ZJ.textPrimary)
                        .padding(.top, 6)

                    localCard
                    appearanceSection
                    contentSection
                    readingSection
                    dataSection
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(QiBackground())
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .tts: TTSConfigView()
                case .backup: BackupView()
                case .cookies: CookieManageView()
                case .cloud: CloudSyncView()
                case .replaceRules: ReplaceRulesView()
                }
            }
            .sheet(isPresented: $showReaderSettings) {
                ReaderSettingsSheet(settingsStore: env.settings)
            }
            .sheet(isPresented: $showAppearance) { AppearanceSettingsView() }
            .sheet(isPresented: $showSources) {
                SourcesView().environmentObject(env)
            }
            .alert(placeholder ?? "", isPresented: Binding(get: { placeholder != nil }, set: { if !$0 { placeholder = nil } })) {
                Button("好", role: .cancel) { placeholder = nil }
            }
            .onAppear(perform: handleLaunchArgs)
        }
    }

    private var localCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(ZJ.accent.opacity(0.10)).frame(width: 54, height: 54)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ZJ.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("本地阅读版").font(.system(size: 17, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                Text("书架 \(env.books.books.count) 本 · 书源 \(env.sources.sources.count) 个 · 无账号体系")
                    .font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
            }
            Spacer()
        }
        .qiCard()
    }

    private var appearanceSection: some View {
        sectionCard("界面与布局") {
            row("paintbrush.fill", "外观 / 配色", value: ZJPaletteStore.current.name) { showAppearance = true }
            row("circle.lefthalf.filled", "深浅色", value: ZJPaletteStore.current.isDark ? "深色" : "浅色") { showAppearance = true }
            row("rectangle.grid.3x2", "书架布局", value: "3 列网格") {
                placeholder = "列表/网格切换与列数设置将在 P0-07 上线。"
            }
        }
    }

    private var contentSection: some View {
        sectionCard("内容与书源") {
            row("speaker.wave.2.fill", "朗读源管理", value: "\(env.tts.availableSources.count) 个", route: .tts)
            row("antenna.radiowaves.left.and.right", "书源管理", value: "\(env.sources.sources.count) 个") {
                showSources = true
            }
            row("wand.and.stars", "替换净化", value: "\(ReplaceRuleStore.shared.rules.count) 条", route: .replaceRules)
            row("list.bullet.indent", "目录规则", value: "未接入") {
                placeholder = "目录规则将随 P0-04 上线：去重、排序、卷名识别。"
            }
        }
    }

    private var readingSection: some View {
        sectionCard("阅读体验") {
            row("textformat.size", "阅读设置", value: "主题/显示/朗读") {
                showReaderSettings = true
            }
            row("textformat", "字体管理", value: "\(env.settings.settings.fontFamily.name)") {
                placeholder = "自定义字体导入将在 P1-06 上线。"
            }
            row("square.stack.3d.up", "章节预缓存", value: "内存") {
                placeholder = "章节磁盘缓存将在 P0-05 上线。"
            }
            row("paintpalette.fill", "主题 / 显示", value: env.settings.settings.theme.name) {
                showReaderSettings = true
            }
        }
    }

    private var dataSection: some View {
        sectionCard("数据与备份") {
            row("externaldrive.badge.icloud", "备份与同步", value: "WebDAV") { path = [.backup] }
            row("icloud", "iCloud 同步", value: "设置/进度/评论") { path = [.cloud] }
            row("network", "Cookie 管理", value: "\(CookieStore.shared.cookieCount) 条") { path = [.cookies] }
            row("doc.on.doc", "恢复与迁移", value: "备份页") { path = [.backup] }
        }
    }

    private var aboutCard: some View {
        HStack {
            Text("指尖阅读 \(version)").font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
            Spacer()
            Text("基于栖阅行为规格重建").font(.system(size: 11)).foregroundStyle(ZJ.textTertiary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ZJ.textSecondary)
                .padding(.leading, 6)
                .padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.04), radius: 16, y: 6)
        }
    }

    @ViewBuilder
    private func row(_ icon: String, _ title: String, value: String? = nil, route: Route? = nil, action: (() -> Void)? = nil) -> some View {
        let body = HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZJ.accent)
                .frame(width: 30, height: 30)
                .background(ZJ.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ZJ.textPrimary)
            Spacer()
            if let value {
                Text(value).font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ZJ.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        if let route {
            NavigationLink(value: route) { body }
                .buttonStyle(.plain)
        } else {
            Button {
                action?()
            } label: { body }
            .buttonStyle(.plain)
        }
    }

    private func handleLaunchArgs() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-autoOpenTTSConfig") { path = [.tts] }
        if args.contains("-autoOpenBackup") { path = [.backup] }
        if args.contains("-autoOpenCookies") { path = [.cookies] }
        if args.contains("-autoOpenCloud") { path = [.cloud] }
        if args.contains("-autoOpenReplaceRules") { path = [.replaceRules] }
        if args.contains("-showReaderSettings") { showReaderSettings = true }
        if args.contains("-showAppearance") { showAppearance = true }
    }
}
