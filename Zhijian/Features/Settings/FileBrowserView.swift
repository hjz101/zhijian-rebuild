// FileBrowserView.swift — 简化文件管理器（App Documents 浏览/导入/删除/重命名）
import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @State private var currentDir: URL = Self.documentsURL
    @State private var items: [URL] = []
    @State private var showImporter = false
    @State private var renaming: URL?
    @State private var renameText = ""
    @State private var alert: String?
    @State private var moveSource: URL?
    @State private var moveIsCopy = false
    @State private var moveDestinations: [URL] = []
    @State private var showMovePicker = false

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var body: some View {
        List {
            Section {
                ForEach(items, id: \.absoluteString) { url in
                    HStack {
                        Image(systemName: isDir(url) ? "folder.fill" : "doc")
                            .foregroundStyle(isDir(url) ? ZJ.celadon : ZJ.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent).font(.system(size: 14)).foregroundStyle(ZJ.textPrimary)
                            if !isDir(url) {
                                Text(ByteCountFormatter.string(fromByteCount: fileSize(url), countStyle: .file))
                                    .font(.system(size: 10)).foregroundStyle(ZJ.textTertiary)
                            }
                        }
                        Spacer()
                        if isDir(url) {
                            Button { enter(url) } label: { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(ZJ.textTertiary) }
                                .buttonStyle(.plain)
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button { renaming = url; renameText = url.lastPathComponent } label: { Label("重命名", systemImage: "pencil") }
                        Button { moveSource = url; moveIsCopy = false; loadDestinations(); showMovePicker = true } label: { Label("移动到…", systemImage: "folder") }
                        Button { moveSource = url; moveIsCopy = true; loadDestinations(); showMovePicker = true } label: { Label("复制到…", systemImage: "doc.on.doc") }
                        Button(role: .destructive) { delete(url) } label: { Label("删除", systemImage: "trash") }
                    }
                }
                .onDelete(perform: deleteRows)
            } header: {
                Text("\(currentDir.lastPathComponent) / \(items.count) 项")
            }
        }
        .navigationTitle("文件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if currentDir != Self.documentsURL {
                    Button("上级") { enter(currentDir.deletingLastPathComponent()) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
            }
        }
        .onAppear(perform: reload)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .plainText, .pdf, .image],
                      allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    let data = try Data(contentsOf: url)
                    let dest = currentDir.appendingPathComponent(url.lastPathComponent)
                    try data.write(to: dest, options: .atomic)
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                reload()
            } catch {
                present("导入失败：\(error.localizedDescription)")
            }
        }
        .alert("重命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("确定") {
                if let url = renaming {
                    let dest = url.deletingLastPathComponent().appendingPathComponent(renameText)
                    try? FileManager.default.moveItem(at: url, to: dest)
                }
                renaming = nil
                reload()
            }
        }
        .sheet(isPresented: $showMovePicker) {
            NavigationStack {
                List {
                    ForEach(moveDestinations, id: \.absoluteString) { dir in
                        Button {
                            performMove(to: dir)
                            showMovePicker = false
                        } label: {
                            Label(dir.lastPathComponent, systemImage: "folder")
                        }
                    }
                }
                .navigationTitle(moveIsCopy ? "复制到…" : "移动到…")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { showMovePicker = false } } }
            }
        }
        .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("好", role: .cancel) { alert = nil }
        }
    }

    private func isDir(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func enter(_ dir: URL) {
        currentDir = dir
        reload()
    }

    private func reload() {
        let fm = FileManager.default
        var list = (try? fm.contentsOfDirectory(at: currentDir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])) ?? []
        list.sort {
            let a = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let b = (try? $1.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if a != b { return a }
            return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        items = list
    }

    private func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    private func loadDestinations() {
        let fm = FileManager.default
        var dirs: [URL] = []
        func collect(_ dir: URL) {
            dirs.append(dir)
            for child in ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []) {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
                    collect(child)
                }
            }
        }
        collect(Self.documentsURL)
        moveDestinations = dirs
    }

    private func performMove(to dir: URL) {
        guard let source = moveSource else { return }
        let destination = dir.appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default
        if moveIsCopy {
            try? fm.copyItem(at: source, to: destination)
        } else {
            try? fm.moveItem(at: source, to: destination)
        }
        moveSource = nil
        reload()
    }

    private func deleteRows(at offsets: IndexSet) {
        for index in offsets where items.indices.contains(index) {
            try? FileManager.default.removeItem(at: items[index])
        }
        reload()
    }

    private func present(_ text: String) {
        alert = text
    }
}
