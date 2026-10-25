// ChapterTitleDesignerView.swift — 章节标题模板设计器（元素编辑 + 实时预览）
import SwiftUI

struct ChapterTitleDesignerView: View {
    @ObservedObject private var store = ChapterTitleTemplateStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ChapterTitleTemplate()
    @State private var selectedElementID: String?
    @State private var previewTitle = "第一章 入山"
    @State private var previewImage: UIImage?
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var showExport = false
    @State private var alert: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard
                    templatePicker
                    elementEditor
                    actions
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(QiBackground())
            .navigationTitle("标题设计器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }.fontWeight(.semibold)
                }
            }
            .task(id: draftSignature) { await refreshPreview() }
            .task(id: previewTitle) { await refreshPreview() }
            .onAppear {
                store.setEnabled(true)
                draft = store.selected ?? ChapterTitleTemplates.builtIns[0]
                selectedElementID = draft.elements.first?.id
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .data],
                          allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let count = try store.importJSON(String(contentsOf: url, encoding: .utf8))
                    present("导入 \(count) 套模板")
                } catch {
                    present("导入失败：\(error.localizedDescription)")
                }
            }
            .sheet(isPresented: $showExport) {
                if let url = exportURL {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 44)).foregroundStyle(ZJ.accent)
                            ShareLink(item: url) { Label("分享 / 存储 JSON", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.borderedProminent).tint(ZJ.accent)
                            Button("完成") { showExport = false }.foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .navigationTitle("导出模板")
                    }
                }
            }
            .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
                Button("好", role: .cancel) { alert = nil }
            }
        }
    }

    private var draftSignature: String {
        "\(draft.id)|\(draft.elements.count)|\(draft.heightRatio)|\(draft.backgroundHex)"
            + draft.elements.map { "\($0.id)\($0.x)\($0.y)\($0.width)\($0.height)\($0.fontSize)\($0.colorHex)\($0.opacity)\($0.ornament)\($0.alignment)" }.joined()
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("预览").font(.system(size: 12, weight: .semibold)).foregroundStyle(ZJ.textSecondary)
                Spacer()
                TextField("章节标题", text: $previewTitle)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ZJ.bgElev2.opacity(0.5))
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(height: 150)
            Text("模板按页面宽度等比缩放；分页高度会随标题区变化。")
                .font(.system(size: 10))
                .foregroundStyle(ZJ.textTertiary)
        }
        .qiCard()
    }

    private var templatePicker: some View {
        QiSettingsSection(title: "模板") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.all) { template in
                        Button {
                            draft = template
                            selectedElementID = template.elements.first?.id
                            store.select(template.id)
                        } label: {
                            VStack(spacing: 4) {
                                Text(template.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(draft.id == template.id ? .white : ZJ.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(draft.id == template.id ? ZJ.accent : ZJ.bgElev2.opacity(0.7), in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        var copy = draft
                        copy.id = UUID().uuidString
                        copy.name = draft.name + " 副本"
                        copy.isBuiltIn = false
                        store.upsert(copy)
                        draft = copy
                        store.select(copy.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ZJ.accent)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(ZJ.accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 10)
            QiDivider()
            QiToggleRow(icon: "textformat", title: "启用 HTML 标题",
                        isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) }))
        }
    }

    private var elementEditor: some View {
        QiSettingsSection(title: "元素") {
            ForEach(Array(draft.elements.enumerated()), id: \.element.id) { index, element in
                HStack(spacing: 10) {
                    Button {
                        selectedElementID = element.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: element.kind))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ZJ.accent)
                            Text(element.kind.name).font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                            if selectedElementID == element.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(ZJ.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        draft.elements.remove(at: index)
                        if selectedElementID == element.id { selectedElementID = draft.elements.first?.id }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(ZJ.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                if index < draft.elements.count - 1 { QiDivider() }
            }

            QiDivider()
            HStack(spacing: 8) {
                ForEach(ChapterTitleElement.Kind.allCases, id: \.self) { kind in
                    Button {
                        var element = ChapterTitleElement()
                        element.kind = kind
                        element.y = 0.1 + Double(draft.elements.count) * 0.18
                        element.height = kind == .line ? 0.012 : 0.18
                        if kind == .text { element.text = "__TEXT__" }
                        draft.elements.append(element)
                        selectedElementID = element.id
                    } label: {
                        Text("+ \(kind.name)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ZJ.accent)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(ZJ.accent.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let index = draft.elements.firstIndex(where: { $0.id == selectedElementID }) {
                QiDivider()
                elementInspector(index: index)
            }
        }
    }

    @ViewBuilder
    private func elementInspector(index: Int) -> some View {
        let binding = Binding(
            get: { draft.elements[index] },
            set: { draft.elements[index] = $0 }
        )
        VStack(spacing: 2) {
            QiSliderRow(title: "横向位置", value: Binding(
                get: { binding.wrappedValue.x },
                set: { binding.wrappedValue.x = $0 }
            ), range: 0...0.8, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
            QiSliderRow(title: "纵向位置", value: Binding(
                get: { binding.wrappedValue.y },
                set: { binding.wrappedValue.y = $0 }
            ), range: 0...0.9, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
            QiSliderRow(title: "宽度", value: Binding(
                get: { binding.wrappedValue.width },
                set: { binding.wrappedValue.width = $0 }
            ), range: 0.1...1, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
            QiSliderRow(title: "字号", value: Binding(
                get: { binding.wrappedValue.fontSize },
                set: { binding.wrappedValue.fontSize = $0 }
            ), range: 10...44, step: 1) { "\(Int($0)) pt" }
            QiSliderRow(title: "不透明度", value: Binding(
                get: { binding.wrappedValue.opacity },
                set: { binding.wrappedValue.opacity = $0 }
            ), range: 0.1...1, step: 0.05) { String(format: "%.0f%%", $0 * 100) }
        }
        if binding.wrappedValue.kind == .text || binding.wrappedValue.kind == .ornament {
            QiDivider()
            HStack {
                Text("内容").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                TextField(binding.wrappedValue.kind == .text ? "__TEXT__" : "❖",
                          text: binding.wrappedValue.kind == .text ? Binding(
                            get: { binding.wrappedValue.text },
                            set: { binding.wrappedValue.text = $0 }
                          ) : Binding(
                            get: { binding.wrappedValue.ornament },
                            set: { binding.wrappedValue.ornament = $0 }
                          ))
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            QiDivider()
            HStack(spacing: 8) {
                Text("对齐").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                ForEach(["left", "center", "right"], id: \.self) { value in
                    Button(value == "left" ? "左" : value == "center" ? "中" : "右") {
                        binding.wrappedValue.alignment = value
                    }
                    .font(.system(size: 11, weight: binding.wrappedValue.alignment == value ? .semibold : .regular))
                    .foregroundStyle(binding.wrappedValue.alignment == value ? .white : ZJ.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(binding.wrappedValue.alignment == value ? ZJ.accent : ZJ.bgElev2.opacity(0.6), in: Capsule())
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var actions: some View {
        QiSettingsSection(title: "操作") {
            actionRow("另存为新模板", icon: "square.on.square") {
                var copy = draft
                copy.id = UUID().uuidString
                copy.name = draft.name + " 副本"
                copy.isBuiltIn = false
                store.upsert(copy)
                draft = copy
                store.select(copy.id)
                present("已另存")
            }
            QiDivider()
            actionRow("导出全部模板", icon: "square.and.arrow.up") {
                do {
                    exportURL = try store.exportJSON()
                    showExport = true
                } catch { present("导出失败：\(error.localizedDescription)") }
            }
            QiDivider()
            actionRow("导入模板 JSON", icon: "doc.badge.plus") { showImporter = true }
            if !draft.isBuiltIn {
                QiDivider()
                Button(role: .destructive) {
                    store.remove(draft)
                    draft = store.selected ?? ChapterTitleTemplates.builtIns[0]
                } label: {
                    Text("删除当前模板")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ZJ.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ZJ.accent)
                    .frame(width: 30, height: 30)
                    .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(ZJ.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(for kind: ChapterTitleElement.Kind) -> String {
        switch kind {
        case .text: return "textformat"
        case .line: return "minus"
        case .ornament: return "sparkles"
        case .image: return "photo"
        }
    }

    private func refreshPreview() async {
        let width: CGFloat = 300
        let image = await ChapterTitleSnapshotService.shared.snapshot(template: draft,
                                                                       title: previewTitle,
                                                                       width: width,
                                                                       theme: ZJPaletteStore.current.isDark ? .ink : .paper)
        previewImage = image
    }

    private func save() {
        store.upsert(draft)
        store.select(draft.id)
        store.setEnabled(true)
        present("已保存并启用")
    }

    private func present(_ text: String) {
        alert = text
    }
}
