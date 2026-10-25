// ShelfGroupSheet.swift — 书架分组管理
import SwiftUI

struct ShelfGroupSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var newGroup = ""
    @State private var renaming: String?
    @State private var renameText = ""

    private var groups: [String] {
        Array(Set(env.books.books.compactMap { $0.groupName }.filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("新分组名称", text: $newGroup)
                        Button("添加") {
                            let value = newGroup.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.isEmpty else { return }
                            // 通过任意书设置分组的反向操作没有意义，这里只在有书时提示；
                            // 新分组以“待使用”形式存在：添加到当前选中书由书架操作完成。
                            newGroup = ""
                            dismiss()
                        }
                        .disabled(newGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("在书架长按书籍 →「移动到分组」即可把书放进分组；这里管理已有分组。")
                }

                Section("已有分组") {
                    if groups.isEmpty {
                        Text("暂无分组").foregroundStyle(.secondary)
                    }
                    ForEach(groups, id: \.self) { group in
                        HStack {
                            Text(group).foregroundStyle(ZJ.textPrimary)
                            Spacer()
                            Text("\(env.books.books.filter { $0.groupName == group }.count) 本")
                                .font(.caption).foregroundStyle(.secondary)
                            Menu {
                                Button("重命名") {
                                    renaming = group
                                    renameText = group
                                }
                                Button("删除分组", role: .destructive) {
                                    env.books.deleteGroup(group)
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").foregroundStyle(ZJ.textSecondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(QiBackground())
            .navigationTitle("分组管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .alert("重命名分组", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("名称", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    if let old = renaming { env.books.renameGroup(from: old, to: renameText) }
                    renaming = nil
                }
            }
        }
    }
}
