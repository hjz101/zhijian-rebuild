// GroupPickerSheet.swift — 把书移动到分组
import SwiftUI

struct GroupPickerSheet: View {
    let book: Book
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var newGroup = ""

    private var groups: [String] {
        Array(Set(env.books.books.compactMap { $0.groupName }.filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        env.books.setGroup(book.id, group: nil)
                        dismiss()
                    } label: {
                        HStack {
                            Text("未分组").foregroundStyle(ZJ.textPrimary)
                            Spacer()
                            if book.groupName == nil { Image(systemName: "checkmark").foregroundStyle(ZJ.accent) }
                        }
                    }
                    ForEach(groups, id: \.self) { group in
                        Button {
                            env.books.setGroup(book.id, group: group)
                            dismiss()
                        } label: {
                            HStack {
                                Text(group).foregroundStyle(ZJ.textPrimary)
                                Spacer()
                                if book.groupName == group { Image(systemName: "checkmark").foregroundStyle(ZJ.accent) }
                            }
                        }
                    }
                } header: {
                    Text("移动到分组")
                }

                Section("新建分组") {
                    HStack {
                        TextField("分组名称", text: $newGroup)
                        Button("创建并移入") {
                            let value = newGroup.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.isEmpty else { return }
                            env.books.setGroup(book.id, group: value)
                            dismiss()
                        }
                        .disabled(newGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(QiBackground())
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
