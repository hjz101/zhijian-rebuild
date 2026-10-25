// BackupView.swift — 本地 .zjbk 备份/恢复 + WebDAV 配置/上传/下载
//
// 入口由 Lead 在 SettingsView 中加入，例如：
// NavigationLink("备份与同步") { BackupView() }
import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        BackupContent(backup: env.backup)
    }
}

private struct BackupContent: View {
    @ObservedObject var backup: BackupService
    @ObservedObject var webdav: WebDAVConfigStore

    @State private var exportURL: URL?
    @State private var showExportSheet = false
    @State private var showImporter = false
    @State private var showRestoreConfirm = false
    @State private var pendingRestoreURL: URL?
    @State private var editingConfig: WebDAVConfig?
    @State private var downloadedURL: URL?
    @State private var remoteBackups: [RemoteBackupItem] = []
    @State private var busyMessage: String?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var encryptBackup = false
    @State private var backupPassword = ""
    @State private var restorePassword = ""
    @State private var showRestorePassword = false

    init(backup: BackupService) {
        self.backup = backup
        _webdav = ObservedObject(wrappedValue: backup.webdav)
    }

    var body: some View {
        Form {
            localSection
            webdavSection
            if webdav.activeConfig != nil {
                remoteSection
            }
            infoSection
        }
        .scrollContentBackground(.hidden)
        .background(QiBackground())
        .tint(ZJ.accent)
        .navigationTitle("备份与同步")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: backupUTTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingRestoreURL = url
                // 等待文件选择器完全收起再弹确认框，避免 presentation 冲突
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    showRestoreConfirm = true
                }
            case .failure(let error):
                presentAlert("选择备份失败", error.localizedDescription)
            }
        }
        .confirmationDialog(
            "恢复备份会覆盖当前书架、书源、阅读设置与 TTS 源，确定继续？",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("恢复", role: .destructive) {
                if let url = pendingRestoreURL { beginRestore(url) }
            }
            Button("取消", role: .cancel) { pendingRestoreURL = nil }
        }
        .sheet(isPresented: $showExportSheet) {
            exportSheet
        }
        .sheet(isPresented: $showRestorePassword) {
            restorePasswordSheet
        }
        .sheet(item: $editingConfig) { config in
            NavigationStack {
                WebDAVConfigEditorView(config: config) { updated in
                    webdav.add(updated)
                    if webdav.activeConfigID == nil { webdav.setActive(updated.id) }
                    editingConfig = nil
                } onCancel: {
                    editingConfig = nil
                }
            }
        }
        .alert(alertTitle.isEmpty ? "提示" : alertTitle, isPresented: $showAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-backupEncryptOn") {
                encryptBackup = true
                backupPassword = "test-123"
            }
        }
        .overlay {
            if let busyMessage {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: ZJ.s3) {
                        ProgressView()
                        Text(busyMessage)
                            .font(.footnote)
                    }
                    .padding(ZJ.s5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ZJ.rMd))
                }
            }
        }
    }

    // MARK: 本地

    private var localSection: some View {
        Section {
            HStack {
                Label("最近本地备份", systemImage: "clock")
                Spacer()
                Text(displayDate(backup.lastLocalBackupAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $encryptBackup) {
                Label("加密备份（AES-GCM）", systemImage: "lock.shield")
            }
            .tint(ZJ.accent)

            if encryptBackup {
                SecureField("备份密码", text: $backupPassword)
                    .textContentType(.newPassword)
            }

            Button {
                exportBackup()
            } label: {
                Label("导出 .zjbk 备份", systemImage: "square.and.arrow.up")
            }

            Button {
                showImporter = true
            } label: {
                Label("从文件恢复…", systemImage: "arrow.down.doc")
            }

            if let summary = backup.lastRestoreSummary {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近恢复：\(displayDate(summary.restoredAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.localizedDescription)
                        .font(.footnote)
                    if let name = summary.remoteFileName {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("本地备份")
        } footer: {
            Text("备份容器为 ZIP + manifest.json，包含 bookshelf / sources / settings / tts_sources；不复制本地书正文与 QiReader 资源。开启加密后使用 PBKDF2-HMAC-SHA256 + AES-GCM，恢复时需要密码。")
        }
    }

    // MARK: WebDAV 配置

    private var webdavSection: some View {
        Section {
            if webdav.configs.isEmpty {
                Text("尚未配置 WebDAV")
                    .foregroundStyle(.secondary)
            }

            ForEach(webdav.configs) { config in
                Button {
                    webdav.setActive(config.id)
                } label: {
                    HStack(spacing: ZJ.s3) {
                        Image(systemName: webdav.activeConfigID == config.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(webdav.activeConfigID == config.id ? ZJ.celadon : ZJ.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(config.name)
                                .foregroundStyle(ZJ.textPrimary)
                            Text(config.url.isEmpty ? "未配置 URL" : "\(config.url)/\(config.directory)")
                                .font(.caption2)
                                .foregroundStyle(ZJ.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        webdav.remove(config)
                        if webdav.activeConfigID != config.id { remoteBackups = [] }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        editingConfig = config
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(ZJ.celadon)
                }
            }

            Button {
                editingConfig = webdav.makeBlank()
            } label: {
                Label("新增 WebDAV 配置", systemImage: "plus.circle")
            }

            if let active = webdav.activeConfig {
                Button {
                    uploadBackup(active)
                } label: {
                    Label("上传备份到 WebDAV", systemImage: "icloud.and.arrow.up")
                }

                Button {
                    downloadLatestBackup(active)
                } label: {
                    Label("下载最新备份", systemImage: "icloud.and.arrow.down")
                }

                Button {
                    testWebDAV(active)
                } label: {
                    Label("测试 WebDAV 连接", systemImage: "network")
                }

                HStack {
                    Label("最近上传", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text(displayDate(backup.lastWebDAVUploadAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("最近下载", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text(displayDate(backup.lastWebDAVDownloadAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let downloadedURL {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已下载：\(downloadedURL.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            pendingRestoreURL = downloadedURL
                            showRestoreConfirm = true
                        } label: {
                            Label("恢复此备份", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
        } header: {
            Text("WebDAV")
        } footer: {
            Text("⚠️ WebDAV 密码当前以明文保存在 Application Support/Zhijian/webdav.json（未使用 Keychain）。备份包可在上方开启 AES-GCM 加密，上传第三方 WebDAV 前建议开启。")
        }
    }

    // MARK: 远程列表

    private var remoteSection: some View {
        Section {
            HStack {
                Text("远程备份")
                Spacer()
                Button {
                    if let active = webdav.activeConfig { refreshRemote(active) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption)
            }

            if remoteBackups.isEmpty {
                Text("暂无远程备份，可先上传一份")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(remoteBackups) { item in
                HStack(spacing: ZJ.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.footnote)
                            .lineLimit(1)
                        Text(remoteSubtitle(item))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if let active = webdav.activeConfig { download(item, from: active) }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下载 \(item.fileName)")
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if let active = webdav.activeConfig {
                            deleteRemote(item, from: active)
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("WebDAV 文件")
        }
    }

    private var infoSection: some View {
        Section("说明") {
            Text("· 备份格式：`.zjbk` = 标准 ZIP（store），根目录 `manifest.json` 带版本/时间/设备/计数；可用系统解压工具查看。")
                .font(.footnote)
            Text("· 恢复是整体替换：书架、书源、阅读设置、TTS 源；本地书正文文件不包含在备份中。")
                .font(.footnote)
            Text("· WebDAV 采用 PROPFIND / MKCOL / PUT / GET，目录不存在会自动创建；仅上传 `.zjbk` 文件。")
                .font(.footnote)
        }
    }

    // MARK: 操作

    private func exportBackup() {
        if encryptBackup && backupPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            presentAlert("请设置备份密码", "开启加密备份后，密码不能为空。")
            return
        }
        do {
            exportURL = try backup.export(password: encryptBackup ? backupPassword : nil)
            showExportSheet = true
        } catch {
            presentAlert("导出失败", error.localizedDescription)
        }
    }

    private func beginRestore(_ url: URL) {
        if BackupService.isEncryptedFile(at: url) {
            pendingRestoreURL = url
            restorePassword = ""
            showRestorePassword = true
        } else {
            performRestore(url)
        }
    }

    private func performRestore(_ url: URL, password: String? = nil) {
        busyMessage = "正在恢复备份…"
        Task {
            defer {
                busyMessage = nil
                pendingRestoreURL = nil
            }
            do {
                try await backup.restore(url: url, password: password)
                let summary = backup.lastRestoreSummary
                presentAlert("恢复完成", summary?.localizedDescription ?? "已恢复")
            } catch {
                presentAlert("恢复失败", error.localizedDescription)
            }
        }
    }

    private func uploadBackup(_ config: WebDAVConfig) {
        if encryptBackup && backupPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            presentAlert("请设置备份密码", "开启加密备份后，密码不能为空。")
            return
        }
        busyMessage = "正在上传备份…"
        Task {
            defer { busyMessage = nil }
            do {
                let item = try await backup.uploadBackup(to: config, password: encryptBackup ? backupPassword : nil)
                presentAlert("上传成功", "\(item.fileName)")
                remoteBackups = (try? await backup.listRemoteBackups(from: config)) ?? remoteBackups
            } catch {
                presentAlert("上传失败", error.localizedDescription)
            }
        }
    }

    private func downloadLatestBackup(_ config: WebDAVConfig) {
        busyMessage = "正在下载最新备份…"
        Task {
            defer { busyMessage = nil }
            do {
                let url = try await backup.downloadLatestBackup(from: config)
                downloadedURL = url
                presentAlert("下载成功", url.lastPathComponent)
                remoteBackups = (try? await backup.listRemoteBackups(from: config)) ?? remoteBackups
            } catch {
                presentAlert("下载失败", error.localizedDescription)
            }
        }
    }

    private func refreshRemote(_ config: WebDAVConfig) {
        busyMessage = "正在读取 WebDAV 目录…"
        Task {
            defer { busyMessage = nil }
            do {
                remoteBackups = try await backup.listRemoteBackups(from: config)
                if remoteBackups.isEmpty {
                    presentAlert("目录为空", "WebDAV 目录中没有 .zjbk 备份")
                }
            } catch {
                presentAlert("读取失败", error.localizedDescription)
            }
        }
    }

    private func download(_ item: RemoteBackupItem, from config: WebDAVConfig) {
        busyMessage = "正在下载 \(item.fileName)…"
        Task {
            defer { busyMessage = nil }
            do {
                downloadedURL = try await backup.downloadBackup(named: item.fileName, from: config)
                presentAlert("下载成功", item.fileName)
            } catch {
                presentAlert("下载失败", error.localizedDescription)
            }
        }
    }

    private func deleteRemote(_ item: RemoteBackupItem, from config: WebDAVConfig) {
        busyMessage = "正在删除…"
        Task {
            defer { busyMessage = nil }
            do {
                try await backup.deleteRemoteBackup(named: item.fileName, from: config)
                remoteBackups.removeAll { $0.id == item.id }
            } catch {
                presentAlert("删除失败", error.localizedDescription)
            }
        }
    }

    private func testWebDAV(_ config: WebDAVConfig) {
        busyMessage = "正在测试连接…"
        Task {
            defer { busyMessage = nil }
            do {
                try await backup.testWebDAV(config)
                presentAlert("连接成功", "WebDAV 认证与目录访问正常")
            } catch {
                presentAlert("连接失败", error.localizedDescription)
            }
        }
    }

    // MARK: 工具

    private var backupUTTypes: [UTType] {
        var types: [UTType] = []
        if let zjbk = UTType(filenameExtension: "zjbk", conformingTo: .archive) {
            types.append(zjbk)
        }
        types.append(.zip)
        types.append(.data)
        return types
    }

    private func displayDate(_ date: Date?) -> String {
        guard let date else { return "从未" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func remoteSubtitle(_ item: RemoteBackupItem) -> String {
        var parts: [String] = []
        if let date = item.modifiedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_Hans_CN")
            formatter.dateFormat = "MM-dd HH:mm"
            parts.append(formatter.string(from: date))
        }
        if let size = item.size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.isEmpty ? "远程备份" : parts.joined(separator: " · ")
    }

    private func presentAlert(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private var restorePasswordSheet: some View {
        NavigationStack {
            VStack(spacing: ZJ.s4) {
                Image(systemName: "lock.doc")
                    .font(.system(size: 42))
                    .foregroundStyle(ZJ.accent)
                Text("该备份已加密")
                    .font(.headline)
                Text("输入导出备份时设置的密码")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SecureField("备份密码", text: $restorePassword)
                    .textContentType(.password)
                    .padding(12)
                    .background(ZJ.bgElev1, in: RoundedRectangle(cornerRadius: 10))
                Button {
                    guard let url = pendingRestoreURL else { return }
                    showRestorePassword = false
                    performRestore(url, password: restorePassword)
                } label: {
                    Text("解密并恢复")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ZJ.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(restorePassword.isEmpty)
                Button("取消") {
                    showRestorePassword = false
                    pendingRestoreURL = nil
                }
                .foregroundStyle(.secondary)
            }
            .padding(ZJ.s6)
            .navigationTitle("输入备份密码")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var exportSheet: some View {
        NavigationStack {
            VStack(spacing: ZJ.s5) {
                Image(systemName: "archivebox")
                    .font(.system(size: 44))
                    .foregroundStyle(ZJ.accent)
                Text("备份已生成")
                    .font(.headline)
                Text("书架 \(backup.books.books.count) 本 · 书源 \(backup.sources.sources.count) 个 · TTS \(backup.ttsSources.sources.count) 个")
                Label(encryptBackup ? "已加密（需要密码恢复）" : "未加密", systemImage: encryptBackup ? "lock.fill" : "lock.open")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("分享 / 存储 .zjbk", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ZJ.accent)
                }
                Button("完成") { showExportSheet = false }
                    .foregroundStyle(.secondary)
            }
            .padding(ZJ.s6)
            .navigationTitle("导出备份")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - WebDAV 配置编辑

private struct WebDAVConfigEditorView: View {
    @State private var draft: WebDAVConfig
    private let onSave: (WebDAVConfig) -> Void
    private let onCancel: () -> Void

    init(config: WebDAVConfig, onSave: @escaping (WebDAVConfig) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: config)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $draft.name)
                TextField("服务器 URL（如 https://dav.example.com/remote.php/dav/files/me）",
                          text: $draft.url, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(2...4)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("目录（如 ZhijianBackups）", text: $draft.directory)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("连接")
            } footer: {
                Text("目录不存在时上传会自动 MKCOL 创建，支持多级目录。")
            }

            Section {
                TextField("用户名", text: $draft.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("密码", text: $draft.password)
            } header: {
                Text("Basic Auth")
            } footer: {
                Text("⚠️ 密码明文保存于本机 Application Support/Zhijian/webdav.json，请勿使用主账号密码。")
            }
        }
        .navigationTitle(draft.name.isEmpty ? "WebDAV 配置" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(draft)
                }
                .disabled(draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
