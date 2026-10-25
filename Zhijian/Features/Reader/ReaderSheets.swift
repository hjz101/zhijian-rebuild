// ReaderSheets.swift — 目录 Sheet 与阅读设置 Sheet（主题 / 字体 / 字号 / 行距 / 段距 / 模式）
import SwiftUI

// MARK: - 目录 / 书签 / 笔记

struct ReaderCatalogSheet: View {
    enum Tab: String, CaseIterable { case chapters = "目录", bookmarks = "书签", notes = "笔记" }

    let model: ReaderViewModel
    let theme: ReaderTheme

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .chapters
    @State private var query = ""

    private var filteredChapters: [(offset: Int, element: Chapter)] {
        let all = Array(model.chapters.enumerated())
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return all }
        return all.filter { $0.element.title.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("分类", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch tab {
                case .chapters: chaptersList
                case .bookmarks: bookmarksList
                case .notes: notesList
                }
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .tint(theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.background)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onAppear {
            for arg in ProcessInfo.processInfo.arguments {
                if arg == "-catalogTab=bookmarks" { tab = .bookmarks }
                if arg == "-catalogTab=notes" { tab = .notes }
            }
        }
    }

    private var title: String {
        switch tab {
        case .chapters: return "目录 · \(model.chapters.count) 章"
        case .bookmarks: return "书签 · \(model.bookmarks.count)"
        case .notes: return "笔记 · \(model.notes.count)"
        }
    }

    // MARK: 章节

    private var chaptersList: some View {
        ScrollViewReader { proxy in
            List {
                if filteredChapters.isEmpty {
                    emptyRow("没有匹配的章节")
                } else {
                    ForEach(filteredChapters.indices, id: \.self) { index in
                        let item = filteredChapters[index]
                        chapterRow(item.offset, chapter: item.element)
                            .listRowBackground(
                                item.offset == model.currentChapterIndex
                                    ? theme.accent.opacity(0.10) : Color.clear
                            )
                            .listRowSeparatorTint(theme.text.opacity(0.08))
                            .id(item.element.id)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onAppear {
                guard let currentID = model.currentChapter?.id else { return }
                DispatchQueue.main.async { proxy.scrollTo(currentID, anchor: .center) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索章节")
        }
    }

    private func chapterRow(_ offset: Int, chapter: Chapter) -> some View {
        let isCurrent = offset == model.currentChapterIndex
        return Button {
            dismiss()
            Task { await model.selectChapter(offset) }
        } label: {
            HStack(spacing: 10) {
                Text("\(offset + 1)")
                    .font(.system(size: 11, weight: isCurrent ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isCurrent ? theme.accent : theme.secondary)
                    .frame(minWidth: 30, alignment: .trailing)
                Text(chapter.title)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? theme.accent : theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isCurrent {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 书签

    private var bookmarksList: some View {
        List {
            if model.bookmarks.isEmpty {
                emptyRow("还没有书签：阅读页右上角点击书签图标添加")
            } else {
                ForEach(model.bookmarks) { bm in
                    Button {
                        dismiss()
                        Task { await model.jumpToBookmark(chapterIndex: bm.chapterIndex, pageIndex: bm.pageIndex) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bm.chapterTitle)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(theme.text)
                                    .lineLimit(1)
                                Text("第 \(bm.pageIndex + 1) 页 · \(Self.dateText(bm.createdAt))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(role: .destructive) { model.removeBookmark(bm.id) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: 笔记 / 划线

    private var notesList: some View {
        List {
            if model.notes.isEmpty {
                emptyRow("还没有划线或笔记：长按选中正文，在菜单中选择「划线」或「笔记」")
            } else {
                ForEach(model.notes) { ann in
                    Button {
                        dismiss()
                        Task { await model.jumpToBookmark(chapterIndex: ann.chapterIndex, pageIndex: 0) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: ann.kind == .note ? "note.text" : "highlighter")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.accent)
                                Text(ann.chapterTitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(Self.dateText(ann.createdAt))
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.secondary)
                            }
                            Text(ann.text)
                                .font(.system(size: 14, design: .serif))
                                .foregroundStyle(theme.text)
                                .lineLimit(2)
                                .padding(.leading, 2)
                            if let note = ann.note, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.secondary)
                                    .padding(.leading, 2)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(role: .destructive) { model.removeAnnotation(ann.id) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(theme.secondary)
            .listRowBackground(Color.clear)
            .padding(.vertical, 20)
    }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - 设置

struct ReaderSettingsSheet: View {
    @ObservedObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showHighlightRules = false
    @State private var showTitleDesigner = false
    @State private var showBackground = false
    @State private var showThemePackages = false
    @State private var showBubbleImport = false
    @State private var showCustomTheme = false

    private var theme: ReaderTheme { settingsStore.settings.theme }
    private var settings: ReadingSettings { settingsStore.settings }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ZJ.s4) {
                    themeSection
                    typeSection
                    titleSection
                    spacingSection
                    modeSection
                    highlightSection
                    bubbleSection
                }
                .padding(.horizontal, ZJ.s5)
                .padding(.top, ZJ.s3)
                .padding(.bottom, ZJ.s8)
            }
            .background(QiBackground())
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .tint(ZJ.accent)
                }
            }
        }
        .sheet(isPresented: $showHighlightRules) {
            HighlightRulesSheet(settingsStore: settingsStore)
        }
        .sheet(isPresented: $showTitleDesigner) {
            ChapterTitleDesignerView()
        }
        .sheet(isPresented: $showBackground) {
            ReaderBackgroundSettingsView()
        }
        .sheet(isPresented: $showThemePackages) {
            ReaderThemePackageView()
                .environmentObject(AppEnvironment.shared)
        }
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ZJ.bgBase)
        .preferredColorScheme(ZJPaletteStore.current.isDark ? .dark : .light)
    }

    // MARK: 主题

    private var themeSection: some View {
        section("主题") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)], spacing: 14) {
                ForEach(ReaderTheme.allCases) { candidate in
                    themeDot(candidate)
                }
                // 自定义配色入口
                Button {
                    showCustomTheme = true
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [ZJ.bgElev2, ZJ.textTertiary.opacity(0.4)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 40, height: 40)
                            Image(systemName: "paintpalette")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(ZJ.accent)
                        }
                        Text("自定义")
                            .font(.system(size: 11, weight: settings.customPalette != nil ? .semibold : .regular))
                            .foregroundStyle(settings.customPalette != nil ? ZJ.accent : ZJ.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if settings.customPalette != nil {
                Button {
                    settingsStore.settings.customPalette = nil
                } label: {
                    HStack {
                        Text("清除自定义配色").font(.system(size: 12)).foregroundStyle(ZJ.error)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func themeDot(_ candidate: ReaderTheme) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settingsStore.settings.customPalette = nil
                settingsStore.settings.theme = candidate
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(candidate.background)
                        .frame(width: 40, height: 40)
                    Circle()
                        .strokeBorder(
                            (settings.customPalette == nil && candidate == theme)
                                ? candidate.accent : candidate.text.opacity(0.12),
                            lineWidth: (settings.customPalette == nil && candidate == theme) ? 2 : 0.5
                        )
                        .frame(width: 40, height: 40)
                    if settings.customPalette == nil, candidate == theme {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(candidate.accent)
                    }
                }
                Text(candidate.name)
                    .font(.system(size: 11, weight: (settings.customPalette == nil && candidate == theme) ? .semibold : .regular))
                    .foregroundStyle((settings.customPalette == nil && candidate == theme) ? ZJ.accent : ZJ.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 字体 / 字号

    private var typeSection: some View {
        section("字体") {
            Picker("字体", selection: bind(\.fontFamily)) {
                ForEach(ReaderFontFamily.allCases) { family in
                    Text(family.name).tag(family)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text("字号")
                    .font(.system(size: 13))
                    .foregroundStyle(ZJ.textPrimary)
                Spacer()
                Text("\(Int(settings.fontSize)) pt")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(ZJ.accent)
            }
            Slider(value: bind(\.fontSize), in: 14...34, step: 1)
                .tint(ZJ.accent)
        }
    }

    // MARK: 章节标题设计器

    private var titleSection: some View {
        section("章节标题") {
            Picker("对齐", selection: bind(\.chapterTitleAlignment)) {
                ForEach(ReadingSettings.TitleAlignment.allCases, id: \.self) { value in
                    Text(value.name).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text("标题大小").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Text(String(format: "%.2fx", settings.chapterTitleScale))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(ZJ.accent)
            }
            Slider(value: bind(\.chapterTitleScale), in: 1.0...1.8, step: 0.02)
                .tint(ZJ.accent)

            Picker("装饰", selection: bind(\.chapterTitleDecoration)) {
                ForEach(ReadingSettings.TitleDecoration.allCases, id: \.self) { value in
                    Text(value.name).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: 自动高亮

    private var highlightSection: some View {
        section("自动高亮") {
            Button {
                showHighlightRules = true
            } label: {
                HStack {
                    Label("高亮规则", systemImage: "highlighter")
                        .font(.system(size: 13))
                        .foregroundStyle(ZJ.textPrimary)
                    Spacer()
                    Text("\(settings.highlightRules.filter(\.enabled).count) 条启用")
                        .font(.system(size: 12))
                        .foregroundStyle(ZJ.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(ZJ.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 行距 / 段距 / 页边距

    private var spacingSection: some View {
        section("排版") {
            sliderRow("行距", value: settings.lineHeight, binding: bind(\.lineHeight), range: 0...24)
            sliderRow("段距", value: settings.paragraphSpacing, binding: bind(\.paragraphSpacing), range: 0...28)
            sliderRow("页边距", value: settings.horizontalPadding, binding: bind(\.horizontalPadding), range: 12...40)
        }
    }

    // MARK: 翻页模式 / 页码

    private var modeSection: some View {
        section("阅读模式") {
            Picker("翻页模式", selection: bind(\.pageMode)) {
                Text("分页").tag(ReadingSettings.PageMode.paged)
                Text("滚动").tag(ReadingSettings.PageMode.scroll)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle(isOn: bind(\.showPageNumber)) {
                Text("显示页码")
                    .font(.system(size: 13))
                    .foregroundStyle(ZJ.textPrimary)
            }
            .tint(ZJ.accent)

            Toggle(isOn: bind(\.traditional)) {
                Text("正文繁体")
                    .font(.system(size: 13))
                    .foregroundStyle(ZJ.textPrimary)
            }
            .tint(ZJ.accent)

            HStack {
                Text("JS 执行器").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Picker("", selection: Binding(
                    get: { settingsStore.settings.jsExecutorMode },
                    set: { settingsStore.settings.jsExecutorMode = $0 }
                )) {
                    Text("自动").tag(0)
                    Text("仅 JSC").tag(1)
                    Text("WebView 优先").tag(2)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(ZJ.accent)
            }
            .padding(.vertical, 4)

            Toggle(isOn: bind(\.longChapterAutoPaged)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("长章自动分页")
                        .font(.system(size: 13))
                        .foregroundStyle(ZJ.textPrimary)
                    Text("滚动模式下超长章节（>6 万字）自动切分页，缓解卡顿")
                        .font(.system(size: 10))
                        .foregroundStyle(ZJ.textTertiary)
                }
            }
            .tint(ZJ.accent)

            Divider().opacity(0.5)

            HStack {
                Text("翻页动画")
                    .font(.system(size: 13))
                    .foregroundStyle(ZJ.textPrimary)
                Spacer()
                Picker("", selection: bind(\.pageTurnAnimation)) {
                    ForEach(ReadingSettings.PageTurnAnimation.allCases, id: \.self) { item in
                        Text(item.name).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(ZJ.accent)
            }

            Button {
                showThemePackages = true
            } label: {
                HStack {
                    Text(LocalizationManager.tr("reader.themePackage")).font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                    Spacer()
                    Text("\(ReaderThemePackageStore.shared.all.count) 套")
                        .font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(ZJ.textTertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                showBackground = true
            } label: {
                HStack {
                    Text(LocalizationManager.tr("reader.bgImage")).font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                    Spacer()
                    Text(ReaderBackgroundStore.shared.enabled ? "已启用" : "未启用")
                        .font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(ZJ.textTertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                showTitleDesigner = true
            } label: {
                HStack {
                    Text("章节标题设计器").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                    Spacer()
                    Text(ChapterTitleTemplateStore.shared.enabled ? "已启用" : "未启用")
                        .font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(ZJ.textTertiary)
                }
            }
            .buttonStyle(.plain)

            Toggle(isOn: bind(\.twoPageEnabled)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("双页模式")
                        .font(.system(size: 13))
                        .foregroundStyle(ZJ.textPrimary)
                    Text("横屏 / iPad 左右两栏")
                        .font(.system(size: 10))
                        .foregroundStyle(ZJ.textTertiary)
                }
            }
            .tint(ZJ.accent)

            Toggle(isOn: bind(\.volumeButtonPageTurn)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("音量键翻页")
                        .font(.system(size: 13))
                        .foregroundStyle(ZJ.textPrimary)
                    Text("音量键翻页且不改变系统音量")
                        .font(.system(size: 10))
                        .foregroundStyle(ZJ.textTertiary)
                }
            }
            .tint(ZJ.accent)
        }
    }

    // MARK: 气泡样式（P2-09 / R2-05）

    private var bubbleSection: some View {
        bubbleSectionBody
            .sheet(isPresented: $showBubbleImport) {
                BubbleImportSheet(settingsStore: settingsStore)
            }
    }

    private var bubbleSectionBody: some View {
        section("段评气泡") {
            HStack {
                Text("颜色").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                ForEach(["#E8663D", "#4E8F86", "#D9A441", "#5C6BC0", "#8D6E63"], id: \.self) { hex in
                    Button {
                        settingsStore.settings.bubbleColorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex) ?? ZJ.accent)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(
                                    settingsStore.settings.bubbleColorHex == hex ? ZJ.accent : Color.clear,
                                    lineWidth: 1.5
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            QiSliderRow(title: "圆角", value: Binding(
                get: { settingsStore.settings.bubbleCornerRadius },
                set: { settingsStore.settings.bubbleCornerRadius = $0 }
            ), range: 8...24, step: 1) { "\(Int($0))" }

            HStack {
                Text("图标").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                ForEach(["💬", "💭", "📝", "✍️"], id: \.self) { icon in
                    Button(icon) {
                        settingsStore.settings.bubbleIcon = icon
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(settingsStore.settings.bubbleIcon == icon ? ZJ.accent : ZJ.textSecondary)
                    .padding(6)
                    .background(settingsStore.settings.bubbleIcon == icon ? ZJ.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Text("皮肤").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                ForEach(["胶囊", "圆角", "对话气泡"], id: \.self) { skin in
                    let index = ["胶囊", "圆角", "对话气泡"].firstIndex(of: skin) ?? 0
                    Button(skin) {
                        settingsStore.settings.bubbleSkin = index
                    }
                    .font(.system(size: 11, weight: settingsStore.settings.bubbleSkin == index ? .semibold : .regular))
                    .foregroundStyle(settingsStore.settings.bubbleSkin == index ? .white : ZJ.textSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(settingsStore.settings.bubbleSkin == index ? ZJ.accent : ZJ.bgElev2.opacity(0.6), in: Capsule())
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            Button {
                showBubbleImport = true
            } label: {
                HStack {
                    Text("导入 .qibubble 样式").font(.system(size: 12, weight: .medium)).foregroundStyle(ZJ.accent)
                    Spacer()
                    Image(systemName: "square.and.arrow.down").font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 组件

    private func sliderRow(
        _ title: String,
        value: Double,
        binding: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(ZJ.textPrimary)
                Spacer()
                Text("\(Int(value))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(ZJ.textSecondary)
            }
            Slider(value: binding, in: range, step: 1)
                .tint(ZJ.accent)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ZJ.s3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(ZJ.textSecondary)
            content()
        }
        .padding(ZJ.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ZJ.rLg, style: .continuous)
                .fill(theme.isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ZJ.rLg, style: .continuous)
                .strokeBorder(ZJ.textPrimary.opacity(0.07), lineWidth: 0.5)
        )
    }

    private func bind<Value>(_ keyPath: WritableKeyPath<ReadingSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - .qibubble 导入（R2-05）

private struct BubbleImportSheet: View {
    let settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var alert: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 40)).foregroundStyle(ZJ.accent)
                Text("导入栖阅/第三方 .qibubble 段评气泡样式 JSON")
                    .font(.system(size: 13)).foregroundStyle(ZJ.textSecondary)
                Button {
                    showImporter = true
                } label: {
                    Label("选择 .qibubble 文件", systemImage: "doc.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(ZJ.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(QiBackground())
            .navigationTitle("导入气泡样式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json, .data],
                          allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    let style = try ExternalThemeImporter.importBubble(data: data)
                    var settings = settingsStore.settings
                    settings.bubbleColorHex = style.colorHex
                    settings.bubbleCornerRadius = style.corner
                    settings.bubbleIcon = style.icon
                    settings.bubbleSkin = style.skin
                    settingsStore.settings = settings
                    dismiss()
                } catch {
                    alert = error.localizedDescription
                }
            }
            .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
                Button("好", role: .cancel) { alert = nil }
            }
        }
    }
}

// MARK: - 自定义阅读配色编辑器（THEME-V2 阶段一）

private struct CustomThemeEditor: View {
    let settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReaderCustomPalette

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        _draft = State(initialValue: settingsStore.settings.customPalette
            ?? ReaderCustomPalette(backgroundHex: settingsStore.settings.theme.backgroundHex,
                                   textHex: settingsStore.settings.theme.textHex,
                                   secondaryHex: settingsStore.settings.theme.secondaryHex,
                                   accentHex: settingsStore.settings.theme.accentHex,
                                   surfaceHex: settingsStore.settings.theme.surfaceHex,
                                   isDark: settingsStore.settings.theme.isDark))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard
                    colorSection
                    Toggle("深色模式", isOn: $draft.isDark)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
            }
            .background(QiBackground())
            .navigationTitle("自定义配色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("应用") {
                        settingsStore.settings.customPalette = draft
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(draft.isDark ? .dark : .light)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第一章 入山").font(.system(size: 17, weight: .bold)).foregroundStyle(draft.text)
            Text("清晨的雾还没有散，山道两旁的松针上挂着水珠。").font(.system(size: 13)).foregroundStyle(draft.secondary)
            HStack(spacing: 6) {
                Text("强调").font(.system(size: 11, weight: .semibold)).foregroundStyle(draft.accent)
                Spacer()
                Text("chrome").font(.system(size: 11)).foregroundStyle(draft.surface)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(draft.background))
        .padding(.horizontal, 20)
    }

    private var colorSection: some View {
        VStack(spacing: 0) {
            colorRow("背景", hex: $draft.backgroundHex, color: Binding(get: { draft.background }, set: { draft.backgroundHex = $0.hexString }))
            Divider().padding(.leading, 56)
            colorRow("正文", hex: $draft.textHex, color: Binding(get: { draft.text }, set: { draft.textHex = $0.hexString }))
            Divider().padding(.leading, 56)
            colorRow("次级文字", hex: $draft.secondaryHex, color: Binding(get: { draft.secondary }, set: { draft.secondaryHex = $0.hexString }))
            Divider().padding(.leading, 56)
            colorRow("强调色", hex: $draft.accentHex, color: Binding(get: { draft.accent }, set: { draft.accentHex = $0.hexString }))
            Divider().padding(.leading, 56)
            colorRow("控制栏/卡片", hex: $draft.surfaceHex, color: Binding(get: { draft.surface }, set: { draft.surfaceHex = $0.hexString }))
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(ZJPaletteStore.current.cardBorder, lineWidth: 0.8))
        .padding(.horizontal, 20)
    }

    private func colorRow(_ title: String, hex: Binding<String>, color: Binding<Color>) -> some View {
        HStack(spacing: 12) {
            ColorPicker("", selection: color).labelsHidden()
            Text(title).font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
            Spacer()
            TextField("#RRGGBB", text: hex)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: hex.wrappedValue) { _, _ in
                    // 规范化 hex（#AARRGGBB → #RRGGBB）
                    hex.wrappedValue = ExternalThemeImporter.normalizeHex(hex.wrappedValue)
                }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
