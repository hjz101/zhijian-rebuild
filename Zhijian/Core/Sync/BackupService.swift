// BackupService.swift — 本地 .zjbk 备份 / 恢复 + WebDAV 上传下载
import Foundation
import UIKit

private enum BackupFormat {
    static let backupExtension = "zjbk"
    static let supportedVersion = 1
    static let manifestName = "manifest.json"
}

/// 备份服务。
///
/// `.zjbk` 是标准 ZIP（store）：
/// - `manifest.json`（BackupManifest）
/// - `bookshelf.json`（[Book]）
/// - `sources.json`（[BookSource]）
/// - `settings.json`（ReadingSettings）
/// - `tts_sources.json`（[HttpTTS]）
///
/// 不复制本地书正文文件与 QiReader 资源；`manifest.includesLocalBooks = false`。
@MainActor
final class BackupService: ObservableObject {

    let books: BookStore
    let sources: SourceStore
    let settings: SettingsStore
    let ttsSources = TTSSourceStore.shared
    let webdav = WebDAVConfigStore.shared

    @Published private(set) var lastLocalBackupAt: Date?
    @Published private(set) var lastRestoreAt: Date?
    @Published private(set) var lastWebDAVUploadAt: Date?
    @Published private(set) var lastWebDAVDownloadAt: Date?
    @Published private(set) var lastRestoreSummary: BackupRestoreSummary?
    @Published private(set) var isWorking = false

    nonisolated static var backupExtension: String { BackupFormat.backupExtension }
    nonisolated static var supportedVersion: Int { BackupFormat.supportedVersion }
    nonisolated static var manifestName: String { BackupFormat.manifestName }

    private struct BackupState: Codable {
        var lastLocalBackupAt: Date?
        var lastRestoreAt: Date?
        var lastWebDAVUploadAt: Date?
        var lastWebDAVDownloadAt: Date?
        var lastRemoteFileName: String?
    }

    private struct BackupPayload: Sendable {
        var manifest: BackupManifest
        var books: [Book]?
        var sources: [BookSource]?
        var settings: ReadingSettings?
        var ttsSources: [HttpTTS]?
        var annotations: AnnotationBackup?
        var paragraphComments: [ParagraphComment]?
        var chapterComments: [ChapterComment]?
        /// P2-03：本地书正文（local/ 相对路径 → 数据）
        var localBooks: [String: Data]?
        /// 主题包 / 字体 / Cookie（备份分类扩展）
        var themePresets: [ReaderThemePreset]?
        var fontEntries: [CustomFontEntry]?
        var cookies: [String: [String: String]]?
        /// 生态类原始文件（背景/标题模板/替换规则/目录规则）
        var rawEntries: [String: Data] = [:]
    }

    private static let stateFile = "backup_state.json"
    private var state: BackupState

    init(books: BookStore, sources: SourceStore, settings: SettingsStore) {
        self.books = books
        self.sources = sources
        self.settings = settings
        let loaded = AppData.load(BackupState.self, Self.stateFile) ?? BackupState()
        self.state = loaded
        self.lastLocalBackupAt = loaded.lastLocalBackupAt
        self.lastRestoreAt = loaded.lastRestoreAt
        self.lastWebDAVUploadAt = loaded.lastWebDAVUploadAt
        self.lastWebDAVDownloadAt = loaded.lastWebDAVDownloadAt
    }

    // MARK: - 本地导出

    /// 导出到临时目录并返回文件 URL（可直接 ShareLink / 存到“文件”）。
    func export(password: String? = nil, includeLocalBooks: Bool = false) throws -> URL {
        try export(to: nil, password: password, includeLocalBooks: includeLocalBooks)
    }

    func export(to directory: URL?, password: String? = nil, includeLocalBooks: Bool = false) throws -> URL {
        let targetDirectory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ZhijianBackups", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }

        let fileName = "zhijian-\(Self.fileTimestamp(Date())).zjbk"
        let url = targetDirectory.appendingPathComponent(fileName)
        var data = try makeBackupData(includeLocalBooks: includeLocalBooks)
        if let password, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data = try BackupCrypto.encrypt(data, password: password)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }

        state.lastLocalBackupAt = Date()
        persistState()
        return url
    }

    /// 只生成备份数据（不落盘），供测试/预览。
    func makeBackupData(includeLocalBooks: Bool = false) throws -> Data {
        var zip = ZipWriter()
        let manifest = makeManifest(includeLocalBooks: includeLocalBooks)
        zip.add(try Self.encodeJSON(manifest), name: Self.manifestName)
        zip.add(try Self.encodeJSON(books.books), name: "bookshelf.json")
        zip.add(try Self.encodeJSON(sources.sources), name: "sources.json")
        zip.add(try Self.encodeJSON(settings.settings), name: "settings.json")
        zip.add(try Self.encodeJSON(ttsSources.sources), name: "tts_sources.json")
        zip.add(try Self.encodeJSON(AnnotationStore.shared.backup()), name: "annotations.json")
        zip.add(try Self.encodeJSON(ParagraphCommentStore.shared.all()), name: "paragraph_comments.json")
        zip.add(try Self.encodeJSON(ChapterCommentStore.shared.all()), name: "chapter_comments.json")
        // 主题包 / 字体 / Cookie（备份分类扩展）
        let customPresets = ReaderThemePackageStore.shared.all.filter { !$0.isBuiltIn }
        if !customPresets.isEmpty {
            zip.add(try Self.encodeJSON(customPresets), name: "reader_theme.json")
        }
        if let fontEntries = AppData.load([CustomFontEntry].self, "custom_fonts.json"), !fontEntries.isEmpty {
            zip.add(try Self.encodeJSON(fontEntries), name: "custom_fonts.json")
        } else if let payload = try? Data(contentsOf: AppData.root.appendingPathComponent("custom_fonts.json")) {
            zip.add(payload, name: "custom_fonts.json")
        }
        if let cookies = try? Data(contentsOf: AppData.root.appendingPathComponent("cookies.json")) {
            zip.add(cookies, name: "cookies.json")
        }
        // 生态类：背景 / 标题模板 / 替换规则 / 目录规则（ChapterRuleConfig）
        if let background = try? Data(contentsOf: AppData.root.appendingPathComponent("reader_background.json")) {
            zip.add(background, name: "reader_background.json")
        }
        if let templates = try? Data(contentsOf: AppData.root.appendingPathComponent("chapter_title_templates.json")) {
            zip.add(templates, name: "chapter_title_templates.json")
        }
        if let replaceRules = try? Data(contentsOf: AppData.root.appendingPathComponent("replace_rules.json")) {
            zip.add(replaceRules, name: "replace_rules.json")
        }
        if let chapterRules = try? Data(contentsOf: AppData.root.appendingPathComponent("chapter_rule_config.json")) {
            zip.add(chapterRules, name: "chapter_rule_config.json")
        }
        if includeLocalBooks {
            addLocalBooks(to: &zip, manifest: manifest)
        }
        return zip.build()
    }

    /// P2-03：把本地书正文（EPUB / PDF / Manga / local_library.json）打包进 `local/`。
    private func addLocalBooks(to zip: inout ZipWriter, manifest: BackupManifest) {
        let fm = FileManager.default
        let root = AppData.root
        for folder in ["EPUB", "PDF", "Manga"] {
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for item in items {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    addDirectory(item, prefix: "local/\(folder)/\(item.lastPathComponent)", into: &zip)
                } else {
                    if let data = try? Data(contentsOf: item) {
                        zip.add(data, name: "local/\(folder)/\(item.lastPathComponent)")
                    }
                }
            }
        }
        if let libraryData = try? Data(contentsOf: root.appendingPathComponent("local_library.json")) {
            zip.add(libraryData, name: "local/local_library.json")
        }
    }

    private func addDirectory(_ dir: URL, prefix: String, into zip: inout ZipWriter) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for item in items {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                addDirectory(item, prefix: "\(prefix)/\(item.lastPathComponent)", into: &zip)
            } else if let data = try? Data(contentsOf: item) {
                zip.add(data, name: "\(prefix)/\(item.lastPathComponent)")
            }
        }
    }

    private func makeManifest(includeLocalBooks: Bool = false) -> BackupManifest {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let themeCount = ReaderThemePackageStore.shared.all.filter { !$0.isBuiltIn }.count
        let fontCount = (AppData.load([CustomFontEntry].self, "custom_fonts.json") ?? []).count
        let replaceCount = (AppData.load([ReplaceRule].self, "replace_rules.json") ?? []).count
        let counts: [String: Int] = [
            "bookshelf": books.books.count,
            "sources": sources.sources.count,
            "settings": 1,
            "ttsSources": ttsSources.sources.count,
            "annotations": AnnotationStore.shared.annotations.count,
            "paragraphComments": ParagraphCommentStore.shared.items.count,
            "chapterComments": ChapterCommentStore.shared.items.count,
            "readerTheme": themeCount,
            "customFonts": fontCount,
            "cookies": 1,
            "readerBackground": 1,
            "titleTemplates": 1,
            "replaceRules": replaceCount,
            "chapterRules": 1,
        ]
        var categories = ["bookshelf", "sources", "settings", "tts_sources", "annotations", "paragraph_comments", "chapter_comments",
                          "reader_theme", "custom_fonts", "cookies", "reader_background", "title_templates", "replace_rules", "chapter_rules"]
        if includeLocalBooks { categories.append("local_books") }
        return BackupManifest(
            version: Self.supportedVersion,
            appVersion: "\(shortVersion) (\(build))",
            createdAt: Date(),
            deviceName: UIDevice.current.name,
            counts: counts,
            includesLocalBooks: includeLocalBooks,
            categories: categories
        )
    }

    // MARK: - 恢复

    /// 读取 `.zjbk` 并整体替换书架 / 书源 / 设置 / TTS 源。
    func restore(url: URL, password: String? = nil) async throws {
        isWorking = true
        defer { isWorking = false }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.corrupt(error.localizedDescription)
        }

        let payload = try await Task.detached(priority: .userInitiated) {
            if BackupCrypto.isEncrypted(data) {
                guard let password, !password.isEmpty else { throw BackupError.encryptedNeedsPassword }
                return try Self.decodeBackup(try BackupCrypto.decrypt(data, password: password))
            }
            return try Self.decodeBackup(data)
        }.value
        apply(payload, remoteFileName: nil)
    }

    /// WebDAV 下载最新备份并立即恢复。
    @discardableResult
    func restoreFromWebDAV(config: WebDAVConfig, password: String? = nil) async throws -> URL {
        let url = try await downloadLatestBackup(from: config)
        try await restore(url: url, password: password)
        state.lastRemoteFileName = url.lastPathComponent
        persistState()
        return url
    }

    private func apply(_ payload: BackupPayload, remoteFileName: String?) {
        if let localBooks = payload.localBooks, !localBooks.isEmpty {
            restoreLocalBooks(localBooks)
        }
        if let newBooks = payload.books {
            for book in books.books { books.remove(book) }
            for book in newBooks { books.add(book) }
        }
        if let newSources = payload.sources {
            sources.replaceAll(newSources)
        }
        if let newSettings = payload.settings {
            settings.settings = newSettings
        }
        if let newTTS = payload.ttsSources {
            ttsSources.replaceAll(newTTS)
        }
        if let newAnnotations = payload.annotations {
            AnnotationStore.shared.replaceAll(newAnnotations)
        }
        if let newComments = payload.paragraphComments {
            ParagraphCommentStore.shared.replaceAll(newComments)
        }
        if let newChapterComments = payload.chapterComments {
            ChapterCommentStore.shared.replaceAll(newChapterComments)
        }
        // 主题包 / 字体 / Cookie 恢复（备份分类扩展）
        if let themePresets = payload.themePresets {
            AppData.save(themePresets, "reader_theme_presets.json")
            ReaderThemePackageStore.shared.reload()
        }
        if let fontEntries = payload.fontEntries {
            AppData.save(fontEntries, "custom_fonts.json")
            CustomFontStore.shared.reload()
        }
        if let cookies = payload.cookies {
            CookieStore.shared.replaceAll(cookies)
        }
        // 生态类恢复：直接写回原文件
        for (fileName, data) in payload.rawEntries {
            try? data.write(to: AppData.root.appendingPathComponent(fileName), options: .atomic)
        }
        if payload.rawEntries["reader_background.json"] != nil {
            ReaderBackgroundStore.shared.reload()
        }
        if payload.rawEntries["chapter_title_templates.json"] != nil {
            ChapterTitleTemplateStore.shared.reload()
        }
        if payload.rawEntries["replace_rules.json"] != nil {
            ReplaceRuleStore.shared.reload()
        }

        let now = Date()
        let summary = BackupRestoreSummary(
            books: payload.books?.count ?? books.books.count,
            sources: payload.sources?.count ?? sources.sources.count,
            ttsSources: payload.ttsSources?.count ?? ttsSources.sources.count,
            settingsRestored: payload.settings != nil,
            annotations: payload.annotations?.annotations.count ?? 0,
            paragraphComments: payload.paragraphComments?.count ?? 0,
            chapterComments: payload.chapterComments?.count ?? 0,
            restoredAt: now,
            remoteFileName: remoteFileName
        )
        state.lastRestoreAt = now
        if let remoteFileName { state.lastRemoteFileName = remoteFileName }
        persistState()
        lastRestoreSummary = summary
    }

    // MARK: - WebDAV

    /// 导出当前数据并上传到 WebDAV（目录不存在会自动 MKCOL）。
    @discardableResult
    func uploadBackup(to config: WebDAVConfig, password: String? = nil) async throws -> RemoteBackupItem {
        isWorking = true
        defer { isWorking = false }
        let file = try export(password: password)
        let item = try await WebDAVClient(config: config).upload(fileURL: file)
        state.lastWebDAVUploadAt = Date()
        state.lastRemoteFileName = item.fileName
        persistState()
        return item
    }

    func listRemoteBackups(from config: WebDAVConfig) async throws -> [RemoteBackupItem] {
        isWorking = true
        defer { isWorking = false }
        return try await WebDAVClient(config: config).listBackups()
    }

    @discardableResult
    func downloadBackup(named fileName: String, from config: WebDAVConfig) async throws -> URL {
        isWorking = true
        defer { isWorking = false }
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        guard !safeName.isEmpty, safeName != "/" else {
            throw WebDAVError.invalidResponse("备份文件名为空")
        }
        let destination = try downloadsDirectory().appendingPathComponent(safeName)
        let result = try await WebDAVClient(config: config).download(fileName: safeName, to: destination)
        state.lastWebDAVDownloadAt = Date()
        state.lastRemoteFileName = safeName
        persistState()
        return result
    }

    @discardableResult
    func downloadLatestBackup(from config: WebDAVConfig) async throws -> URL {
        isWorking = true
        defer { isWorking = false }
        let items = try await WebDAVClient(config: config).listBackups()
        guard let latest = items.first else { throw BackupError.emptyRemoteDirectory }
        let destination = try downloadsDirectory().appendingPathComponent(latest.fileName)
        let result = try await WebDAVClient(config: config).download(fileName: latest.fileName, to: destination)
        state.lastWebDAVDownloadAt = Date()
        state.lastRemoteFileName = latest.fileName
        persistState()
        return result
    }

    func deleteRemoteBackup(named fileName: String, from config: WebDAVConfig) async throws {
        isWorking = true
        defer { isWorking = false }
        try await WebDAVClient(config: config).delete(fileName: fileName)
    }

    func testWebDAV(_ config: WebDAVConfig) async throws {
        isWorking = true
        defer { isWorking = false }
        try await WebDAVClient(config: config).checkConnection()
    }

    nonisolated static func isEncryptedFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 64)) ?? Data()
        return header.starts(with: BackupCrypto.magic)
    }

    func downloadsDirectory() throws -> URL {
        let directory = AppData.root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// P2-03：把备份里的 `local/` 写回 AppData.root（EPUB/PDF/Manga 目录 + local_library.json）。
    private func restoreLocalBooks(_ entries: [String: Data]) {
        let fm = FileManager.default
        let root = AppData.root
        for (name, data) in entries.sorted(by: { $0.key < $1.key }) {
            guard name.hasPrefix("local/") else { continue }
            let rel = String(name.dropFirst("local/".count))
            guard !rel.isEmpty else { continue }
            let dest = root.appendingPathComponent(rel).standardizedFileURL
            guard dest.path.hasPrefix(root.standardizedFileURL.path + "/") else { continue }
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: dest, options: .atomic)
        }
    }

    // MARK: - 状态

    private func persistState() {
        AppData.save(state, Self.stateFile)
        lastLocalBackupAt = state.lastLocalBackupAt
        lastRestoreAt = state.lastRestoreAt
        lastWebDAVUploadAt = state.lastWebDAVUploadAt
        lastWebDAVDownloadAt = state.lastWebDAVDownloadAt
    }

    // MARK: - 编解码

    private nonisolated static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private nonisolated static func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        if let value = try? iso.decode(type, from: data) { return value }
        // 兼容旧版/外部工具使用 Unix 时间戳的 JSON
        let plain = JSONDecoder()
        if let value = try? plain.decode(type, from: data) { return value }
        // 保留真正的解码错误信息
        return try iso.decode(type, from: data)
    }

    private nonisolated static func decodeBackup(_ data: Data) throws -> BackupPayload {
        let zip: ZipReader
        do {
            zip = try ZipReader(data: data)
        } catch {
            throw BackupError.notBackup
        }
        guard zip.contains(BackupFormat.manifestName) else { throw BackupError.manifestMissing }

        let manifest: BackupManifest
        do {
            manifest = try decodeJSON(BackupManifest.self, from: zip.read(BackupFormat.manifestName))
        } catch {
            throw BackupError.corrupt("manifest.json 解码失败：\(error.localizedDescription)")
        }
        guard manifest.version <= BackupFormat.supportedVersion else {
            throw BackupError.unsupportedVersion(manifest.version)
        }

        let books = try decodeArray(Book.self, zip: zip, names: ["bookshelf.json", "books.json"])
        let sources = try decodeArray(BookSource.self, zip: zip, names: ["sources.json", "bookSources.json"])
        let ttsSources = try decodeArray(HttpTTS.self, zip: zip, names: ["tts_sources.json", "ttsSources.json"])
        let settings: ReadingSettings? = try decodeFirst(
            ReadingSettings.self, zip: zip, names: ["settings.json", "readingSettings.json"]
        )
        let annotations: AnnotationBackup? = try decodeFirst(
            AnnotationBackup.self, zip: zip, names: ["annotations.json"]
        )
        let paragraphComments = try decodeArray(ParagraphComment.self, zip: zip, names: ["paragraph_comments.json"])
        let chapterComments = try decodeArray(ChapterComment.self, zip: zip, names: ["chapter_comments.json"])

        var localBooks: [String: Data]? = nil
        if manifest.includesLocalBooks {
            localBooks = [:]
            for name in zip.entryNames where name.hasPrefix("local/") {
                if let data = try? zip.read(name) {
                    localBooks?[name] = data
                }
            }
        }
        let themePresets = try? decodeArray(ReaderThemePreset.self, zip: zip, names: ["reader_theme.json"])
        let fontEntries = try? decodeArray(CustomFontEntry.self, zip: zip, names: ["custom_fonts.json"])
        var cookies: [String: [String: String]]? = nil
        if zip.contains("cookies.json"), let data = try? zip.read("cookies.json") {
            cookies = try? Self.decodeJSON([String: [String: String]].self, from: data)
        }
        // 生态类原始文件（背景/标题模板/替换规则/目录规则）——直接按原文件内容保存
        var rawEntries: [String: Data] = [:]
        for entryName in ["reader_background.json", "chapter_title_templates.json", "replace_rules.json", "chapter_rule_config.json"] {
            if zip.contains(entryName), let data = try? zip.read(entryName) {
                rawEntries[entryName] = data
            }
        }

        return BackupPayload(
            manifest: manifest,
            books: books,
            sources: sources,
            settings: settings,
            ttsSources: ttsSources,
            annotations: annotations,
            paragraphComments: paragraphComments,
            chapterComments: chapterComments,
            localBooks: localBooks,
            themePresets: themePresets,
            fontEntries: fontEntries,
            cookies: cookies,
            rawEntries: rawEntries
        )
    }

    private nonisolated static func decodeArray<T: Decodable>(
        _ type: T.Type,
        zip: ZipReader,
        names: [String]
    ) throws -> [T]? {
        guard let name = names.first(where: { zip.contains($0) }) else { return nil }
        do {
            let data = try zip.read(name)
            if name == "bookshelf.json",
               let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let array = wrapper["books"] {
                let normalized = try JSONSerialization.data(withJSONObject: array)
                return try decodeJSON([T].self, from: normalized)
            }
            if name == "sources.json",
               let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let array = wrapper["sources"] {
                let normalized = try JSONSerialization.data(withJSONObject: array)
                return try decodeJSON([T].self, from: normalized)
            }
            return try decodeJSON([T].self, from: data)
        } catch {
            throw BackupError.corrupt("\(name) 解码失败：\(error.localizedDescription)")
        }
    }

    private nonisolated static func decodeFirst<T: Decodable>(
        _ type: T.Type,
        zip: ZipReader,
        names: [String]
    ) throws -> T? {
        guard let name = names.first(where: { zip.contains($0) }) else { return nil }
        do {
            return try decodeJSON(type, from: zip.read(name))
        } catch {
            throw BackupError.corrupt("\(name) 解码失败：\(error.localizedDescription)")
        }
    }

    private static func fileTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
