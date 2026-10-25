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
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ZJ.bgBase)
        .preferredColorScheme(ZJPaletteStore.current.isDark ? .dark : .light)
    }

    // MARK: 主题

    private var themeSection: some View {
        section("主题") {
            HStack(spacing: ZJ.s3) {
                ForEach(ReaderTheme.allCases) { candidate in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                                        candidate == theme ? candidate.accent : candidate.text.opacity(0.12),
                                        lineWidth: candidate == theme ? 2 : 0.5
                                    )
                                    .frame(width: 40, height: 40)
                                if candidate == theme {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(candidate.accent)
                                }
                            }
                            Text(candidate.name)
                                .font(.system(size: 11, weight: candidate == theme ? .semibold : .regular))
                                .foregroundStyle(candidate == theme ? ZJ.accent : ZJ.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
