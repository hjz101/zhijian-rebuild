// ShelfLayoutSettingsView.swift — 书架布局（网格/列表、列数）
import SwiftUI

struct ShelfLayoutSettingsView: View {
    @AppStorage("shelf.listMode") private var listMode = false
    @AppStorage("shelf.columns") private var columns = 3
    @AppStorage("shelf.sort") private var sortKey = "recent"
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var paletteObserver = PaletteObserver.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("书架布局")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(ZJ.textPrimary)

                    VStack(alignment: .leading, spacing: 14) {
                        Picker("显示方式", selection: $listMode) {
                            Text("网格").tag(false)
                            Text("列表").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if !listMode {
                            HStack {
                                Text("每行封面").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                                Spacer()
                                Text("\(columns) 列").font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
                            }
                            Slider(value: Binding(
                                get: { Double(columns) },
                                set: { columns = Int($0.rounded()) }
                            ), in: 2...5, step: 1)
                            .tint(ZJ.accent)
                        }
                    }
                    .qiCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("默认排序").font(.system(size: 13, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                        Picker("排序", selection: $sortKey) {
                            Text("最近阅读").tag("recent")
                            Text("添加时间").tag("added")
                            Text("书名").tag("title")
                        }
                        .pickerStyle(.segmented)
                    }
                    .qiCard()

                    preview

                    Text(listMode ? "列表模式适合书名较长、追求扫读效率。" : "网格模式最多 5 列，封面按 0.72 比例裁切。")
                        .font(.system(size: 11))
                        .foregroundStyle(ZJ.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(QiBackground())
            .navigationTitle("书架布局")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预览").font(.system(size: 12, weight: .semibold)).foregroundStyle(ZJ.textSecondary)
            if listMode {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8).fill(ZJ.bgElev2).frame(width: 42, height: 58)
                        .overlay(Text("山").font(.system(size: 18, design: .serif)).foregroundStyle(ZJ.textSecondary))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("山居书简").font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                        Text("指尖示例").font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                        ProgressView(value: 0.42).tint(ZJ.accent)
                    }
                    Spacer()
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: max(2, min(5, columns))), spacing: 14) {
                    ForEach(0..<max(2, min(5, columns)), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 5) {
                            RoundedRectangle(cornerRadius: 10).fill(ZJ.bgElev2)
                                .aspectRatio(0.72, contentMode: .fit)
                                .overlay(Text("书").font(.system(size: 18, design: .serif)).foregroundStyle(ZJ.textSecondary))
                            Text("示例 \(index + 1)").font(.system(size: 10)).foregroundStyle(ZJ.textSecondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qiCard()
    }
}

/// 让设置页在配色变化时刷新文案/颜色（读取 ZJ 动态色不会自动触发 SwiftUI 更新）。
final class PaletteObserver: ObservableObject {
    static let shared = PaletteObserver()
    @Published private(set) var id = ZJPaletteStore.currentID
    private init() {
        NotificationCenter.default.addObserver(forName: .zjPaletteChanged, object: nil, queue: .main) { [weak self] _ in
            self?.id = ZJPaletteStore.currentID
        }
    }
}
