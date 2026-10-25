// AppEnvironment.swift — 应用级依赖容器与持久化（Lead 维护）
import SwiftUI
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let books: BookStore
    let sources: SourceStore
    let settings: SettingsStore
    let engines: EngineRegistry
    let content: BookContentService
    let tts: TTSController
    let backup: BackupService
    let localLibrary: LocalLibrary

    private init() {
        let books = BookStore()
        let sources = SourceStore()
        let settings = SettingsStore()
        self.books = books
        self.sources = sources
        self.settings = settings
        self.engines = EngineRegistry(sources: sources, settings: settings)
        self.content = BookContentService(books: books, sources: sources)
        self.tts = TTSController()
        self.backup = BackupService(books: books, sources: sources, settings: settings)
        self.localLibrary = LocalLibrary.shared
#if DEBUG
        AppEnvironment.seedDemoSourceIfNeeded(into: sources)
        localLibrary.seedDemoBookIfNeeded(into: books)
        if ProcessInfo.processInfo.arguments.contains("-seedLocalTxt"),
           let url = Bundle.main.url(forResource: "demo-book", withExtension: "txt") {
            _ = try? LocalImportService.shared.importTXT(url: url, into: books)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-backupCryptoTest") {
            BackupCryptoDebugTest.run(backup: self.backup)
        }
        #endif
        if ProcessInfo.processInfo.arguments.contains("-seedCommentReactions") {
            let chapterStore = ChapterCommentStore.shared
            if let first = chapterStore.topLevelComments(bookId: "demo-local-001", chapterIndex: 0).first,
               chapterStore.replies(bookId: "demo-local-001", chapterIndex: 0, parentId: first.id).isEmpty {
                chapterStore.toggleLike(first.id)
                chapterStore.add(bookId: "demo-local-001", chapterIndex: 0, chapterTitle: "第一章 入山",
                                 text: "@阿禾 这段我也很喜欢", replyToId: first.id)
            }
            let paragraphStore = ParagraphCommentStore.shared
            if let first = paragraphStore.topLevelComments(bookId: "demo-local-001", chapterIndex: 0, paragraphIndex: 2).first,
               paragraphStore.replies(bookId: "demo-local-001", chapterIndex: 0, paragraphIndex: 2, parentId: first.id).isEmpty {
                paragraphStore.toggleLike(first.id)
                paragraphStore.add(bookId: "demo-local-001", chapterIndex: 0, paragraphIndex: 2,
                                   text: "@阿禾 同感", replyToId: first.id)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-seedManyChapterComments") {
            let store = ChapterCommentStore.shared
            if store.count(bookId: "demo-local-001", chapterIndex: 0) < 6 {
                for index in 1...6 {
                    store.add(bookId: "demo-local-001", chapterIndex: 0, chapterTitle: "第一章 入山",
                              text: "分页测试评论 #\(index)：这一章的山雾写得很有层次。")
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-seedChapterComments") {
            let store = ChapterCommentStore.shared
            if store.count(bookId: "demo-local-001", chapterIndex: 0) == 0 {
                store.add(bookId: "demo-local-001", chapterIndex: 0, chapterTitle: "第一章 入山",
                          text: "章末这一句收得很稳，期待下一章。")
                store.add(bookId: "demo-local-001", chapterIndex: 0, chapterTitle: "第一章 入山",
                          text: "山雾与书庐的意象很统一。")
            }
        }
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-palette=") }) {
            ZJPaletteStore.applyPreset(String(arg.dropFirst(9)))
        }
        if ProcessInfo.processInfo.arguments.contains("-seedReplaceRules") {
            let existing = ReplaceRuleStore.shared.rules
            if existing.isEmpty {
                ReplaceRuleStore.shared.replaceAll([
                    ReplaceRule(name: "删除广告行", pattern: "【广告】.*", replacement: "",
                                isRegex: true, scope: .content, order: 0),
                    ReplaceRule(name: "删除域名", pattern: "本站域名\\s*\\S+\\s*请勿相信。", replacement: "",
                                isRegex: true, scope: .content, order: 1),
                    ReplaceRule(name: "标题去重章号", pattern: "^第\\d+章\\s*", replacement: "",
                                isRegex: true, scope: .title, order: 2)
                ])
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-readerBackgroundTest") {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600))
            let image = renderer.image { context in
                UIColor(red: 0.55, green: 0.72, blue: 0.62, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
                UIColor(white: 1, alpha: 0.35).setFill()
                context.fill(CGRect(x: 40, y: 120, width: 320, height: 200))
            }
            ReaderBackgroundStore.shared.setImage(image)
            ReaderBackgroundStore.shared.opacity = 0.4
            ReaderBackgroundStore.shared.blur = 8
            let lines = [
                "hasImage=\(ReaderBackgroundStore.shared.hasImage)",
                "enabled=\(ReaderBackgroundStore.shared.enabled)",
                "bytes=\(ReaderBackgroundStore.shared.imageData?.count ?? 0)"
            ]
            try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("reader-background-test.txt"),
                                                     atomically: true, encoding: .utf8)
        }
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-importSourceFile=") }) {
            let name = String(arg.dropFirst("-importSourceFile=".count))
            let candidates = [
                AppData.root.appendingPathComponent(name),
                FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
            ]
            if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                do {
                    try sources.importJSON(text)
                    NSLog("[Seed] imported sources=%d from %@", sources.sources.count, name)
                } catch {
                    NSLog("[Seed] import failed %@", error.localizedDescription)
                }
            } else {
                NSLog("[Seed] file not found %@", name)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-readerPathTest") {
            Task { @MainActor in
                var lines: [String] = []
                guard let source = self.sources.sources.first(where: { ($0.bookSourceUrl).contains("vossc") || $0.bookSourceName.contains("书山") }) else {
                    lines.append("no aggregate source")
                    try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("reader-path-test.txt"), atomically: true, encoding: .utf8)
                    return
                }
                let service = BookContentService(books: self.books, sources: self.sources)
                let pipeline = self.engines.makePipeline(source: source)
                do {
                    let categories = try await pipeline.exploreCategories()
                    guard let category = categories.first else { lines.append("no categories"); return }
                    let books = try await pipeline.explore(category: category, page: 1)
                    guard let first = books.first else { lines.append("no books"); return }
                    let book = Book.remote(first, source: source)
                    lines.append("book=\(book.title) url=\(book.bookUrl?.prefix(50) ?? "-")")
                    let chapters = try await service.chapters(for: book)
                    lines.append("readerChapters=\(chapters.count)")
                    for ch in chapters.prefix(3) {
                        lines.append("  [\(ch.index)] \(ch.title.prefix(20)) url=\(ch.url.prefix(60))")
                    }
                    if let ch = chapters.first {
                        do {
                            let content = try await service.content(for: book, chapter: ch)
                            lines.append("content chars=\(content.text.count) head=\(content.text.prefix(40).replacingOccurrences(of: "\n", with: " "))")
                        } catch {
                            lines.append("content error=\(error.localizedDescription)")
                        }
                    }
                } catch {
                    lines.append("error=\(error.localizedDescription)")
                }
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("reader-path-test.txt"), atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-readerDiag") {
            Task { @MainActor in
                var lines: [String] = []
                guard let source = self.sources.sources.first(where: { ($0.searchUrl ?? "").contains("rulianshi") })
                        ?? self.sources.sources.first(where: { !($0.searchUrl ?? "").isEmpty }) else {
                    lines.append("no searchable source")
                    try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("reader-diag.txt"), atomically: true, encoding: .utf8)
                    return
                }
                lines.append("source=\(source.bookSourceName)")
                let pipeline = self.engines.makePipeline(source: source)
                do {
                    let books = try await pipeline.search("剑来")
                    lines.append("search=\(books.count) first=\(books.first?.name ?? "-")")
                    if let first = books.first {
                        let info = try await pipeline.bookInfo(first)
                        lines.append("detail name=\(info.name) toc=\(info.tocUrl.prefix(60))")
                        let toc = try await pipeline.toc(info)
                        lines.append("toc=\(toc.count) first=\(toc.first?.title ?? "-")")
                        if let ch = toc.first(where: { !$0.isVolume }) {
                            let content = try await pipeline.content(ch, book: info)
                            lines.append("content chars=\(content.content.count) head=\(content.content.prefix(60).replacingOccurrences(of: "\n", with: " "))")
                        }
                    }
                } catch {
                    lines.append("error=\(error.localizedDescription)")
                }
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("reader-diag.txt"), atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-exploreDiag") {
            Task { @MainActor in
                var lines: [String] = []
                guard let source = self.sources.sources.first(where: { !($0.exploreUrl ?? "").isEmpty }) else {
                    lines.append("no source with exploreUrl")
                    try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("explore-diag.txt"), atomically: true, encoding: .utf8)
                    return
                }
                lines.append("source=\(source.bookSourceName)")
                let pipeline = self.engines.makePipeline(source: source)
                lines.append("jsLib=\(pipeline.jsLibStatus ?? "-")")
                do {
                    let categories = try await pipeline.exploreCategories()
                    lines.append("categories=\(categories.count)")
                    lines.append("titles=\(categories.prefix(6).map(\.title).joined(separator: ","))")
                    let attempts_detail = ProcessInfo.processInfo.arguments.contains("-exploreDetail")
                    for category in categories.prefix(2) {
                        do {
                            let books = try await pipeline.explore(category: category, page: 1)
                            lines.append("[\(category.title)] books=\(books.count) first=\(books.first?.name ?? "-") author=\(books.first?.author ?? "-") url=\(books.first?.bookUrl.prefix(60) ?? "-")")
                            if let first = books.first, attempts_detail {
                                do {
                                    let info = try await pipeline.bookInfo(first)
                                    lines.append("  detail ok name=\(info.name) toc=\(info.tocUrl.prefix(70)) cover=\(info.coverUrl.prefix(50))")
                                    let toc = try await pipeline.toc(info)
                                    lines.append("  toc chapters=\(toc.count) first=\(toc.first?.title ?? "-")")
                                    for (i, ch) in toc.prefix(4).enumerated() {
                                        lines.append("    [\(i)] vol=\(ch.isVolume) title=\(ch.title.prefix(24)) url=\(ch.url.prefix(90))")
                                    }
                                    if let ch = toc.first(where: { !$0.isVolume }) {
                                        let content = try await pipeline.content(ch, book: info)
                                        lines.append("  content len=\(content.content.count) head=\(content.content.prefix(50).replacingOccurrences(of: "\n", with: " "))")
                                    }
                                } catch {
                                    lines.append("  detail error=\(error.localizedDescription)")
                                }
                            }
                        } catch {
                            lines.append("[\(category.title)] error=\(error.localizedDescription)")
                        }
                    }
                } catch {
                    lines.append("categories error=\(error.localizedDescription)")
                }
                lines.append("--- diagnostics ---")
                lines.append(contentsOf: pipeline.diagnosticsSnapshot.prefix(40))
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("explore-diag.txt"), atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-webdavMirrorDiffTest") {
            // 离线 diff 自检：验证「只传变化文件」与冲突判定
            let now = Date()
            let local: [String: (size: Int64, mtime: Date)] = [
                "a.zjbk": (100, now),
                "b.zjbk": (200, now),
                "c.zjbk": (300, now)
            ]
            let remote: [String: (size: Int64?, mtime: Date?)] = [
                "a.zjbk": (100, now),                                  // 相同 → unchanged
                "b.zjbk": (201, now.addingTimeInterval(-3600)),        // 大小不同且远端较旧 → upload
                "c.zjbk": (333, now.addingTimeInterval(7200)),         // 大小不同且远端较新 → conflict
                "d.zjbk": (400, now)                                   // 本地没有 → delete
            ]
            let diff = WebDAVMirrorService.diff(local: local, remote: remote)
            let lines = [
                "upload=\(diff.upload.sorted())",
                "unchanged=\(diff.unchanged.sorted())",
                "conflicts=\(diff.conflicts.sorted())",
                "delete=\(diff.delete.sorted())"
            ]
            try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("webdav-mirror-test.txt"),
                                                     atomically: true, encoding: .utf8)
        }
        if ProcessInfo.processInfo.arguments.contains("-i18nAudit") {
            let lines = I18nAudit.run()
            try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("i18n-audit.txt"),
                                                      atomically: true, encoding: .utf8)
            NSLog("[I18nAudit] %@", lines.first ?? "")
        }
        if ProcessInfo.processInfo.arguments.contains("-webViewJSExecTest") {
            Task {
                let executor = WebViewJSExecutor()
                var lines: [String] = []
                do {
                    let sum = try await Task.detached { try executor.evaluate("1+2*3") }.value
                    lines.append("sum=\(sum) (期望 7)")
                } catch {
                    lines.append("sum=✗ \(error.localizedDescription)")
                }
                do {
                    let obj = try await Task.detached { try executor.evaluate("JSON.stringify({a:1,b:'x'})") }.value
                    lines.append("json=\(obj) (期望 {\"a\":1,\"b\":\"x\"})")
                } catch {
                    lines.append("json=✗ \(error.localizedDescription)")
                }
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("webview-js-test.txt"),
                                                         atomically: true, encoding: .utf8)
                NSLog("[WebViewJS] %@", lines.joined(separator: " | "))
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-archiveImportTest") {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            var lines: [String] = []
            for name in ["archive-imgs.zip", "archive-txt.zip"] {
                let src = URL(fileURLWithPath: "/tmp/\(name)")
                if fm.fileExists(atPath: src.path) {
                    let dest = docs.appendingPathComponent(name)
                    try? fm.copyItem(at: src, to: dest)
                    do {
                        let book = try LocalImportService.shared.importArchive(url: dest, into: self.books)
                        lines.append("\(name) -> \(book.title) chapters=\(book.totalChapters)")
                    } catch {
                        lines.append("\(name) -> ✗ \(error.localizedDescription)")
                    }
                } else {
                    lines.append("\(name) -> 样本缺失（本机无）")
                }
            }
            try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("archive-import-test.txt"),
                                                     atomically: true, encoding: .utf8)
            NSLog("[ArchiveImport] %@", lines.joined(separator: " | "))
        }
        if ProcessInfo.processInfo.arguments.contains("-selfTestSuite") {
            let report = SelfTestSuite.run()
            try? report.write(to: AppData.root.appendingPathComponent("self-test-report.txt"),
                              atomically: true, encoding: .utf8)
            NSLog("[SelfTest] %@", report.replacingOccurrences(of: "\n", with: " | "))
            if ProcessInfo.processInfo.arguments.contains("-sourceRegression") {
                Task { @MainActor in
                    let lines = await self.runSourceRegression()
                    try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("source-regression-report.txt"),
                                                              atomically: true, encoding: .utf8)
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-pcmPlayerTest") {
            Task { @MainActor in
                NSLog("[PCMStream] test begin")
                var lines: [String] = []
                // 合成 0.5s 440Hz 正弦（16kHz/16bit/单声道）
                let count = 16000 / 2
                var samples = [Int16](repeating: 0, count: count)
                for i in 0..<count {
                    let value = sin(2.0 * Double.pi * 440.0 * Double(i) / 16000.0)
                    samples[i] = Int16(value * 12000)
                }
                let data = samples.withUnsafeBytes { Data($0) }
                let converted = PCMStreamPlayer.shared.convertForValidation(data)
                lines.append("pcmBytes=\(data.count) frames=\(converted)")
                // 引擎播放需要真实音频设备（模拟器无渲染设备会阻塞），真机验证
                lines.append("engineNote=\(PCMStreamPlayer.shared.deviceAvailable ? "ok" : "simulator: 真机验证")")
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("pcm-player-test.txt"),
                                                         atomically: true, encoding: .utf8)
                NSLog("[PCMStream] test done frames=\(converted)")
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-autoBackupTest") {
            Task { @MainActor in
                let store = AutoBackupStore.shared
                store.frequency = .daily
                let result = await AutoBackupRunner.runNow(backup: self.backup)
                var lines = [
                    "result=\(result)",
                    "last=\(store.lastAutoBackupAt?.formatted() ?? "nil")",
                    "driveAvailable=\(CloudSyncService.shared.driveAvailable)"
                ]
                if let dir = CloudSyncService.shared.driveDirectory() {
                    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                    lines.append("cloudFiles=\(files.map(\.lastPathComponent))")
                }
                let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("ZhijianAutoBackup", isDirectory: true)
                let fbFiles = (try? FileManager.default.contentsOfDirectory(at: fallback, includingPropertiesForKeys: nil)) ?? []
                lines.append("fallbackFiles=\(fbFiles.map(\.lastPathComponent))")
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("auto-backup-test.txt"),
                                                         atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-keychainTest") {
            var lines: [String] = []
            KeychainStore.set("secret-密码-123", service: "com.zhijian.test", account: "demo")
            let got = KeychainStore.get(service: "com.zhijian.test", account: "demo") ?? "<nil>"
            lines.append("write=get:\(got == "secret-密码-123") value=\(got)")
            KeychainStore.delete(service: "com.zhijian.test", account: "demo")
            lines.append("delete=get:\(KeychainStore.get(service: "com.zhijian.test", account: "demo") == nil)")

            let webdav = WebDAVConfigStore.shared
            let blank = webdav.makeBlank()
            var cfg = blank
            cfg.password = "wd-pw-测试"
            webdav.add(cfg)
            let hydrated = webdav.config(id: cfg.id)?.password ?? ""
            lines.append("webdavRoundtrip=\(hydrated == "wd-pw-测试")")
            let disk = (try? String(contentsOf: AppData.root.appendingPathComponent("webdav.json"), encoding: .utf8)) ?? ""
            lines.append("webdavPlaintextInJSON=\(disk.contains("wd-pw-测试")) (fallback=未签名构建)")
            webdav.remove(id: cfg.id)
            lines.append("webdavDeleted=\(KeychainStore.get(service: KeychainStore.webDAVService, account: cfg.id) == nil)")

            TTSRuntimeStore.shared.setLoginHeader("Token abc123", for: "tts-demo")
            lines.append("ttsRoundtrip=\(TTSRuntimeStore.shared.loginHeader(for: "tts-demo") == "Token abc123")")
            TTSRuntimeStore.shared.removeRuntime(for: "tts-demo")
            lines.append("ttsDeleted=\(TTSRuntimeStore.shared.loginHeader(for: "tts-demo").isEmpty)")
            try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("keychain-test.txt"),
                                                     atomically: true, encoding: .utf8)
        }
        if ProcessInfo.processInfo.arguments.contains("-sourceLoginTest") {
            Task { @MainActor in
                var lines: [String] = []
                guard let source = self.sources.sources.first(where: { ($0.bookSourceUrl).contains("shushan") || $0.bookSourceName.contains("书山") }) else {
                    lines.append("no shushan source")
                    try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("source-login-test.txt"), atomically: true, encoding: .utf8)
                    return
                }
                lines.append("source=\(source.bookSourceName) loginUi=\((source.loginUi ?? "").isEmpty ? "nil" : "yes")")
                let pipeline = SourcePipeline(source: source,
                                              initialCookies: CookieStore.shared.snapshot(),
                                              loginInfo: ["邮箱": "demo@example.com", "密码": "wrong-pass"],
                                              loginHeader: [:],
                                              onCookiesChanged: { CookieStore.onChange($0) })
                do {
                    let headers = try await pipeline.runLoginScript()
                    lines.append("headers=\(headers.keys.sorted().joined(separator: ","))")
                } catch {
                    lines.append("login error=\(error.localizedDescription)")
                }
                lines.append("ajaxStatus=\(pipeline.lastJSAjaxStatus)")
                lines.append("ajaxBody=\(pipeline.lastJSAjaxBody.prefix(120))")
                do {
                    let headers = try await pipeline.runLoginAction("get_cx()", loginInfo: ["邮箱": "demo@example.com", "密码": "wrong-pass"])
                    lines.append("action headers=\(headers.keys.joined(separator: ","))")
                } catch {
                    lines.append("action error=\(error.localizedDescription)")
                }
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("source-login-test.txt"), atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-themePackageTest") {
            Task { @MainActor in
                var lines: [String] = []
                var preset = ReaderThemePackageStore.shared.makePreset(from: settings.settings, name: "测试主题")
                preset.backgroundHex = "#EDE4D4"
                preset.textHex = "#2A241C"
                ReaderThemePackageStore.shared.upsert(preset)
                let url = try ReaderThemePackageStore.shared.exportPackage(preset)
                let imported = try ReaderThemePackageStore.shared.importPackage(url: url)
                lines.append("presets=\(ReaderThemePackageStore.shared.all.count)")
                lines.append("export=\(url.lastPathComponent) bytes=\(try Data(contentsOf: url).count)")
                lines.append("roundtrip=\(imported.name) bg=\(imported.backgroundHex)")
                let fontEntry = CustomFontStore.shared.fonts.first
                lines.append("fonts=\(CustomFontStore.shared.fonts.count) first=\(fontEntry?.displayName ?? "-")")
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("theme-package-test.txt"),
                                                         atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-readerImageTest") {
            let html = """
            <div>第一段文字。</div><img src="/img/a.png" alt="山景"><div>第二段文字。</div>
            <img src="https://example.com/b.png"><div>第三段文字。</div>
            """
            let extracted = ReaderImageExtractor.extract(from: html, baseURL: "https://demo.local/book/1")
            var settings = ReadingSettings()
            settings.theme = .paper
            let sample = ReaderImageStore.placeholder(size: CGSize(width: 200, height: 100), text: "图片")
            let attributed = ReaderTextBuilder.build(title: "第一章 入山", body: extracted.text,
                                                     settings: settings, theme: .paper,
                                                     pageWidth: 300,
                                                     images: extracted.images,
                                                     imageProvider: { _ in sample })
            var attachmentCount = 0
            attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                if value != nil { attachmentCount += 1 }
            }
            let lines = [
                "images=\(extracted.images.count)",
                "firstUrl=\(extracted.images.first?.url ?? "-")",
                "text=\(extracted.text.replacingOccurrences(of: "\n", with: " | "))",
                "attachments=\(attachmentCount)",
                "length=\(attributed.length)"
            ]
            try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("reader-image-test.txt"),
                                                     atomically: true, encoding: .utf8)
        }
        if ProcessInfo.processInfo.arguments.contains("-titleTemplateTest") {
            Task { @MainActor in
                var lines: [String] = []
                let store = ChapterTitleTemplateStore.shared
                store.setEnabled(true)
                store.select("builtin-ornament")
                lines.append("enabled=\(store.enabled) selected=\(store.selected?.name ?? "-")")
                if let template = store.selected {
                    let image = await ChapterTitleSnapshotService.shared.snapshot(template: template,
                                                                                  title: "第一章 入山",
                                                                                  width: 300)
                    lines.append("snapshot=\(image.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "nil")")
                    let html = ChapterTitleHTML.build(template: template, title: "第一章 入山", width: 300, theme: .paper)
                    lines.append("htmlBytes=\(html.utf8.count)")
                    let exported = try? store.exportJSON()
                    lines.append("export=\(exported?.lastPathComponent ?? "-")")
                    lines.append("templates=\(store.all.count)")
                }
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("title-template-test.txt"),
                                                         atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-twoPageTest") {
            var updated = settings.settings
            updated.pageMode = .paged
            updated.twoPageEnabled = true
            settings.settings = updated
        }
        if ProcessInfo.processInfo.arguments.contains("-jsLibTest") {
            let script = """
            function sharedGreeting(name) { return '你好，' + name + '（jsLib）'; }
            var sharedVersion = 'v1';
            """
            var source = BookSource()
            source.bookSourceUrl = "http://localhost/jslib-demo"
            source.bookSourceName = "jsLib 测试源"
            source.enabled = true
            source.jsLib = script
            sources.update(source)
            Task { @MainActor in
                var lines: [String] = []
                let imported = self.sources.sources.contains { $0.bookSourceUrl == "http://localhost/jslib-demo" }
                lines.append("imported=\(imported)")
                if let stored = self.sources.sources.first(where: { $0.bookSourceUrl == "http://localhost/jslib-demo" }) {
                    let pipeline = self.engines.makePipeline(source: stored)
                    let value = try? pipeline.testJsLib()
                    lines.append("jsLibValue=\(value ?? "-")")
                    lines.append("jsLibStatus=\(pipeline.jsLibStatus ?? "-")")
                }
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("jslib-test.txt"),
                                                         atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-searchPageTest") {
            Task { @MainActor in
                var lines: [String] = []
                let p1 = await self.engines.search("剑来", page: 1, useCache: false)
                let p2 = await self.engines.search("剑来", page: 2, useCache: false)
                let start = Date()
                let cached = await self.engines.search("剑来", page: 1, useCache: true)
                let cachedMs = Int(Date().timeIntervalSince(start) * 1000)
                lines.append("page1Groups=\(p1.count) page1Books=\(p1.reduce(0) { $0 + $1.books.count })")
                lines.append("page2Groups=\(p2.count) page2Books=\(p2.reduce(0) { $0 + $1.books.count })")
                lines.append("cachedGroups=\(cached.count) cachedMs=\(cachedMs)")
                lines.append("page1First=\(p1.first?.books.first?.name ?? "-")")
                try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("search-page-test.txt"),
                                                         atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-chapterCacheTest") {
            let bookId = "demo-local-001"
            let chapters = [
                Chapter(id: "\(bookId)#0", index: 0, title: "第一章 入山", url: "https://example.com/1"),
                Chapter(id: "\(bookId)#1", index: 1, title: "第二章 书庐", url: "https://example.com/2")
            ]
            ChapterCacheStore.shared.saveChapters(bookId: bookId, title: "缓存测试书", chapters: chapters)
            ChapterCacheStore.shared.saveContent(bookId: bookId, chapter: chapters[0],
                                                  content: BookChapterContent(title: "第一章 入山", text: String(repeating: "山雾。", count: 200), nextChapterIndex: 1))
            let loadedToc = ChapterCacheStore.shared.loadChapters(bookId: bookId)?.count ?? -1
            let loadedBody = ChapterCacheStore.shared.loadContent(bookId: bookId, chapter: chapters[0])?.text.count ?? -1
            let lines = [
                "toc=\(loadedToc)",
                "bodyChars=\(loadedBody)",
                "size=\(ChapterCacheStore.shared.formattedSize)",
                "books=\(ChapterCacheStore.shared.bookCount) files=\(ChapterCacheStore.shared.chapterFileCount)"
            ]
            try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("chapter-cache-test.txt"),
                                                     atomically: true, encoding: .utf8)
        }
        if ProcessInfo.processInfo.arguments.contains("-chapterRuleTest") {
            var config = ChapterRuleConfig()
            config.titleCleanupRegex = "^(正文|最新章节)\\s*"
            let sample = [
                SourceChapter(index: 0, title: "第3章 风起", url: "3", updateTime: "", isVolume: false),
                SourceChapter(index: 1, title: "第1章 入山", url: "1", updateTime: "", isVolume: false),
                SourceChapter(index: 2, title: "第2章 书庐", url: "2", updateTime: "", isVolume: false),
                SourceChapter(index: 3, title: "第2章 书庐", url: "2", updateTime: "", isVolume: false),
                SourceChapter(index: 4, title: "", url: "empty", updateTime: "", isVolume: false),
                SourceChapter(index: 5, title: "第二卷 远行", url: "v2", updateTime: "", isVolume: false),
                SourceChapter(index: 6, title: "正文 第4章 夜宿", url: "4", updateTime: "", isVolume: false)
            ]
            let result = ChapterRuleEngine.apply(sample, config: config)
            let lines = [
                "count=\(result.chapters.count)",
                "ordered=\(result.chapters.map { ($0.isVolume ? "[卷]" : "") + $0.title }.joined(separator: ","))",
                "duplicates=\(result.removedDuplicates) empty=\(result.removedEmpty) volumes=\(result.detectedVolumes) reversed=\(result.reversed)"
            ]
            try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("chapter-rule-test.txt"),
                                                     atomically: true, encoding: .utf8)
        }
        if ProcessInfo.processInfo.arguments.contains("-replaceRuleTest") {
            let rules = [
                ReplaceRule(name: "删除广告行", pattern: "【广告】.*", replacement: "", isRegex: true, scope: .content),
                ReplaceRule(name: "域名替换", pattern: "(https?://)?[a-z0-9.]+\\.(com|cn)/?", replacement: "[链接]", isRegex: true, scope: .both),
                ReplaceRule(name: "章号去重", pattern: "^第\\d+章\\s*", replacement: "", isRegex: true, scope: .title)
            ]
            let sample = "【广告】点击下载\n正文 www.example.com 到此一游\n第12章 山雨欲来"
            let r = ReplaceRuleEngine.apply(rules, to: sample, scope: .content)
            let t = ReplaceRuleEngine.apply(rules, to: "第12章 山雨欲来", scope: .title)
            let lines = [
                "applied=\(r.applied)",
                "content=\(r.text.replacingOccurrences(of: "\n", with: " | "))",
                "title=\(t.text)",
                "failures=\(r.failures.joined(separator: ","))"
            ]
            try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("replace-rule-test.txt"),
                                                     atomically: true, encoding: .utf8)
        }
        if ProcessInfo.processInfo.arguments.contains("-seedReadingStats") {
            ReadingStatsStore.shared.seedDemo()
        }
        if ProcessInfo.processInfo.arguments.contains("-seedExploreSource"),
           let url = Bundle.main.url(forResource: "demo-explore-source", withExtension: "json"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            try? sources.importJSON(text)
        }
        if ProcessInfo.processInfo.arguments.contains("-seedLoginSource"),
           let url = Bundle.main.url(forResource: "demo-login-source", withExtension: "json"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            try? sources.importJSON(text)
        }
        if ProcessInfo.processInfo.arguments.contains("-seedParagraphComments") {
            let store = ParagraphCommentStore.shared
            if store.counts(bookId: "demo-local-001", chapterIndex: 0).isEmpty {
                store.add(bookId: "demo-local-001", chapterIndex: 0, paragraphIndex: 1,
                          text: "对雾的描写很细腻，像真的走进山里。")
                store.add(bookId: "demo-local-001", chapterIndex: 0, paragraphIndex: 1,
                          text: "这一段的节奏也很舒服。")
                store.add(bookId: "demo-local-001", chapterIndex: 0, paragraphIndex: 2,
                          text: "「书庐」这个意象好，埋下伏笔。")
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-seedHighlightRules") {
            var value = settings.settings
            if value.highlightRules.isEmpty {
                value.highlightRules = [
                    HighlightRule(name: "雾", pattern: "雾", colorHex: "#D9A441"),
                    HighlightRule(name: "书庐", pattern: "书庐", colorHex: "#7FA88A")
                ]
            }
            settings.settings = value
        }
        if ProcessInfo.processInfo.arguments.contains("-titleDesign") {
            var value = settings.settings
            value.chapterTitleAlignment = .leading
            value.chapterTitleScale = 1.5
            value.chapterTitleDecoration = .line
            settings.settings = value
        }
        if ProcessInfo.processInfo.arguments.contains("-systemTTS") {
            tts.selectedSourceID = nil
            TTSSourceStore.shared.remove(id: "ws-debug")
        }
        if ProcessInfo.processInfo.arguments.contains("-wsTTSTest") {
            let wsSource = HttpTTS(id: "ws-debug", name: "WS 本地测试", url: "ws://127.0.0.1:8766",
                                   contentType: "audio/wav", concurrentRate: nil, enabledCookieJar: false,
                                   loginUrl: nil, loginUi: nil, loginCheckJs: nil, header: nil,
                                   jsLib: nil, enabled: true)
            TTSSourceStore.shared.add(wsSource)
            tts.selectedSourceID = "ws-debug"
            tts.play(text: "这是 WebSocket 流式朗读测试。", bookTitle: "WS 测试", chapterTitle: "第一句")
        }
        if ProcessInfo.processInfo.arguments.contains("-epubPaged") {
            settings.settings.pageMode = .paged
        }
        if let modeArg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-jsExecutorMode=") }),
           let mode = Int(modeArg.dropFirst(16)) {
            var s = settings.settings
            s.jsExecutorMode = mode
            settings.settings = s
        }
        if ProcessInfo.processInfo.arguments.contains("-customPaletteTest") {
            var settings2 = settings.settings
            settings2.customPalette = ReaderCustomPalette(
                backgroundHex: "#2B2B33", textHex: "#E6E1D8", secondaryHex: "#9A9388",
                accentHex: "#C9A227", surfaceHex: "#3A3A46", isDark: true)
            settings.settings = settings2
        }
        if ProcessInfo.processInfo.arguments.contains("-scrollMode") {
            settings.settings.pageMode = .scroll
        }
        if ProcessInfo.processInfo.arguments.contains("-readerPaged") {
            settings.settings.pageMode = .paged
        }
        if ProcessInfo.processInfo.arguments.contains("-webdavCommentTest") {
            WebDAVCommentDebugTest.run(backup: backup)
        }
        if ProcessInfo.processInfo.arguments.contains("-commentSyncTest") {
            CommentSyncDebugTest.run()
        }
        if ProcessInfo.processInfo.arguments.contains("-cloudTest") {
            CloudSyncDebugTest.run(settings: settings, books: books)
        }
        if ProcessInfo.processInfo.arguments.contains("-cookieTest") {
            CookieStore.shared.merge(["example.com": ["token": "abc123", "sid": "zj-demo"]])
        }
        if ProcessInfo.processInfo.arguments.contains("-seedManga"),
           let url = Bundle.main.url(forResource: "指尖漫画示例", withExtension: "cbz"),
           !books.books.contains(where: { $0.title == "指尖漫画示例" }) {
            _ = try? LocalImportService.shared.importManga(url: url, into: books)
        }
        if ProcessInfo.processInfo.arguments.contains("-seedPDF"),
           let url = Bundle.main.url(forResource: "指尖PDF示例", withExtension: "pdf"),
           !books.books.contains(where: { $0.title == "指尖PDF示例" }) {
            _ = try? LocalImportService.shared.importPDF(url: url, into: books)
        }
        if ProcessInfo.processInfo.arguments.contains("-seedLongEpub"),
           let url = Bundle.main.url(forResource: "long", withExtension: "epub"),
           !books.books.contains(where: { $0.title == "长章测试" }) {
            _ = try? LocalImportService.shared.importEPUB(url: url, into: books)
        }
        if ProcessInfo.processInfo.arguments.contains("-seedLongTxt") {
            let longBody = String(repeating: "山雾未散。阿禾在山道边等我。我数着石阶，一步，两步，风从谷底翻上来。\n", count: 3000)
            let record = LocalBookRecord(bookId: "demo-long-txt", chapters: [
                LocalChapterRecord(index: 0, title: "第一章 长卷", text: longBody)
            ])
            LocalLibrary.shared.save(record)
            if !books.books.contains(where: { $0.id == "demo-long-txt" }) {
                var book = Book.local(title: "长章TXT测试", author: "指尖示例", fileName: "长章TXT测试.txt")
                book.id = "demo-long-txt"
                book.totalChapters = 1
                book.lastChapter = "第一章 长卷"
                books.add(book)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-seedEpub"),
           let url = Bundle.main.url(forResource: "demo", withExtension: "epub"),
           !books.books.contains(where: { $0.title == "指尖测试书" }) {
            _ = try? LocalImportService.shared.importEPUB(url: url, into: books)
        }
#endif
    }

    private static func seedDemoSourceIfNeeded(into sources: SourceStore) {
        guard sources.sources.isEmpty,
              let url = Bundle.main.url(forResource: "demo-source-rulianshi", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? sources.importJSON(text)
    }
}

// MARK: - JSON 文件存储

enum AppData {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Zhijian", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func url(_ name: String) -> URL { root.appendingPathComponent(name) }
    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }
}

// MARK: - 书架

@MainActor
final class BookStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    private let file = "bookshelf.json"

    init() { books = AppData.load([Book].self, file) ?? [] }

    func add(_ book: Book) {
        if let idx = books.firstIndex(where: { $0.title == book.title && $0.author == book.author && $0.sourceUrl == book.sourceUrl }) {
            books[idx].lastReadAt = Date()
        } else {
            books.append(book)
        }
        persist()
    }
    func remove(_ book: Book) { books.removeAll { $0.id == book.id }; persist() }
    func update(_ book: Book) {
        guard let idx = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[idx] = book; persist()
    }
    func setGroup(_ id: String, group: String?) {
        guard let idx = books.firstIndex(where: { $0.id == id }) else { return }
        books[idx].groupName = (group?.isEmpty == false) ? group : nil
        persist()
    }

    func renameGroup(from old: String, to new: String) {
        let value = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        for idx in books.indices where books[idx].groupName == old {
            books[idx].groupName = value
        }
        persist()
    }

    func deleteGroup(_ name: String) {
        for idx in books.indices where books[idx].groupName == name {
            books[idx].groupName = nil
        }
        persist()
    }

    func markRead(_ id: String, chapter: Int, page: Int, ratio: Double) {
        guard let idx = books.firstIndex(where: { $0.id == id }) else { return }
        books[idx].currentChapterIndex = chapter
        books[idx].currentPageIndex = page
        books[idx].currentScrollRatio = ratio
        books[idx].lastReadAt = Date()
        persist()
    }
    private func persist() { AppData.save(books, file) }
}

// MARK: - 书源

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var sources: [BookSource] = []
    private let file = "sources.json"

    init() { sources = AppData.load([BookSource].self, file) ?? [] }

    func importJSON(_ text: String) throws {
        let list = try BookSourceLoader.load(text)
        for s in list {
            if let idx = sources.firstIndex(where: { $0.bookSourceUrl == s.bookSourceUrl }) {
                sources[idx] = s
            } else {
                sources.append(s)
            }
        }
        persist()
    }
    func remove(_ source: BookSource) { sources.removeAll { $0.bookSourceUrl == source.bookSourceUrl }; persist() }
    func toggle(_ source: BookSource) {
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) else { return }
        sources[idx].enabled = !(sources[idx].enabled ?? true)
        persist()
    }
    func replaceAll(_ list: [BookSource]) { sources = list; persist() }

    func update(_ source: BookSource) {
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) else {
            sources.append(source)
            persist()
            return
        }
        sources[idx] = source
        persist()
    }

    func setGroup(_ group: String?, for source: BookSource) {
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) else { return }
        let value = group?.trimmingCharacters(in: .whitespacesAndNewlines)
        sources[idx].bookSourceGroup = (value?.isEmpty == false) ? value : nil
        persist()
    }

    func setEnabled(_ enabled: Bool, for source: BookSource) {
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) else { return }
        sources[idx].enabled = enabled
        persist()
    }

    var groups: [String] {
        Array(Set(sources.compactMap { $0.bookSourceGroup }.filter { !$0.isEmpty })).sorted()
    }

    func deduplicate() -> Int {
        var seen = Set<String>()
        var removed = 0
        var kept: [BookSource] = []
        for source in sources {
            if seen.contains(source.bookSourceUrl) { removed += 1; continue }
            seen.insert(source.bookSourceUrl)
            kept.append(source)
        }
        if removed > 0 { sources = kept; persist() }
        return removed
    }

    func exportJSON(only source: BookSource? = nil) throws -> URL {
        let list = source.map { [$0] } ?? sources
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        let data = try encoder.encode(list)
        let name = source.map { "\($0.bookSourceName).json" } ?? "zhijian-sources.json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
    private func persist() { AppData.save(sources, file) }
}

// MARK: - 设置

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: ReadingSettings {
        didSet {
            AppData.save(settings, "settings.json")
            HTTPClient.httpsFirstEnabled = settings.httpsFirst
            HTTPClient.currentExecutorMode = settings.jsExecutorMode
        }
    }
    init() {
        settings = AppData.load(ReadingSettings.self, "settings.json") ?? ReadingSettings()
        HTTPClient.httpsFirstEnabled = settings.httpsFirst
        HTTPClient.currentExecutorMode = settings.jsExecutorMode
    }
}

// MARK: - 多源搜索引擎

@MainActor
final class EngineRegistry: ObservableObject {
    let sources: SourceStore
    let settings: SettingsStore
    /// 搜索页缓存：key = keyword|page|sourceCount
    private var searchCache: [String: (date: Date, groups: [(source: BookSource, books: [SourceBook], error: String?)])] = [:]
    private let searchCacheTTL: TimeInterval = 180
    /// P3-05：按源复用 pipeline（避免重复初始化 JSContext），内存紧张/空闲时回收。
    private var pipelineCache: [String: SourcePipeline] = [:]
    private let pipelineCacheLimit = 6
    private var memoryObserver: NSObjectProtocol?
    private var idleTask: Task<Void, Never>?

    init(sources: SourceStore, settings: SettingsStore) {
        self.sources = sources
        self.settings = settings
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.recyclePipelines()
        }
        scheduleIdleRecycle()
    }

    /// 空闲回收：3 分钟无搜索后清空复用的 pipeline（释放 JSContext 内存）。
    private func scheduleIdleRecycle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3 * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.recyclePipelines()
        }
    }

    func enabledSources() -> [BookSource] { sources.sources.filter { $0.enabled ?? true } }

    func makePipeline(source: BookSource) -> SourcePipeline {
        if let cached = pipelineCache[source.bookSourceUrl] { return cached }
        let initial = CookieStore.shared.snapshot()
        let pipeline = SourcePipeline(source: source, initialCookies: initial,
                                      loginInfo: SourceLoginStore.shared.loginInfo(for: source.bookSourceUrl),
                                      loginHeader: SourceLoginStore.shared.loginHeader(for: source.bookSourceUrl),
                                      onCookiesChanged: { CookieStore.onChange($0) })
        if pipelineCache.count >= pipelineCacheLimit {
            let oldest = pipelineCache.keys.first ?? ""
            pipelineCache.removeValue(forKey: oldest)
        }
        pipelineCache[source.bookSourceUrl] = pipeline
        return pipeline
    }

    /// P3-05：内存紧张或空闲时回收复用的 pipeline。
    func recyclePipelines() {
        pipelineCache.removeAll()
    }

    func pipelines() -> [SourcePipeline] {
        enabledSources().map { makePipeline(source: $0) }
    }

    func clearSearchCache() { searchCache.removeAll() }

    /// 搜索完成后重置空闲回收计时。
    private func markActivity() {
        scheduleIdleRecycle()
    }

    func search(_ keyword: String, page: Int = 1, useCache: Bool = true) async -> [(source: BookSource, books: [SourceBook], error: String?)] {
        let enabled = enabledSources()
        let cacheKey = "\(keyword.lowercased())|\(page)|\(enabled.count)"
        if useCache, let cached = searchCache[cacheKey], Date().timeIntervalSince(cached.date) < searchCacheTTL {
            return cached.groups
        }
        let initialCookies = CookieStore.shared.snapshot()
        let loginStates = enabled.reduce(into: [String: (info: [String: String], header: [String: String])]()) { result, source in
            result[source.bookSourceUrl] = (SourceLoginStore.shared.loginInfo(for: source.bookSourceUrl),
                                            SourceLoginStore.shared.loginHeader(for: source.bookSourceUrl))
        }
        return await withTaskGroup(of: (BookSource, [SourceBook], String?, Double).self) { group in
            for source in enabled {
                group.addTask {
                    let started = Date()
                    do {
                        let login = loginStates[source.bookSourceUrl] ?? ([:], [:])
                        let pipeline = SourcePipeline(source: source, initialCookies: initialCookies,
                                                      loginInfo: login.info, loginHeader: login.header,
                                                      onCookiesChanged: { CookieStore.onChange($0) })
                        let books = try await pipeline.search(keyword, page: page)
                        return (source, books, nil, Date().timeIntervalSince(started) * 1000)
                    } catch {
                        return (source, [], error.localizedDescription, Date().timeIntervalSince(started) * 1000)
                    }
                }
            }
            var out: [(BookSource, [SourceBook], String?, Double)] = []
            for await item in group { out.append(item) }
            if Task.isCancelled { return [] }
            for item in out {
                SourceSpeedStore.shared.record(sourceURL: item.0.bookSourceUrl, elapsedMs: Double(item.3))
            }
            let sorted = out.sorted { ($0.1.count) > ($1.1.count) }
                .map { (source: $0.0, books: $0.1, error: $0.2) }
            searchCache[cacheKey] = (Date(), sorted)
            markActivity()
            return sorted
        }
    }

}

#if DEBUG
@MainActor
enum BackupCryptoDebugTest {
    static func run(backup: BackupService) {
        Task { @MainActor in
            var lines: [String] = []
            do {
                let plain = Data("指尖阅读-backup-crypto".utf8)
                let encrypted = try BackupCrypto.encrypt(plain, password: "test-123")
                lines.append("encryptedBytes=\(encrypted.count)")
                lines.append("magicOK=\(BackupCrypto.isEncrypted(encrypted))")
                let decrypted = try BackupCrypto.decrypt(encrypted, password: "test-123")
                lines.append("roundtripOK=\(decrypted == plain)")
                do {
                    _ = try BackupCrypto.decrypt(encrypted, password: "wrong")
                    lines.append("wrongPasswordRejected=false")
                } catch {
                    lines.append("wrongPasswordRejected=true")
                }
                AnnotationStore.shared.addAnnotation(bookId: "demo-local-001", chapterIndex: 0,
                                                     chapterTitle: "第一章 入山", location: 0, length: 4,
                                                     text: "第一章", note: nil, kind: .highlight)
                ParagraphCommentStore.shared.add(bookId: "demo-local-001", chapterIndex: 0,
                                                 paragraphIndex: 0, text: "备份回归段评")
                ChapterCommentStore.shared.add(bookId: "demo-local-001", chapterIndex: 0,
                                              chapterTitle: "第一章 入山", text: "备份回归章末评论")
                lines.append("annotationsBefore=\(AnnotationStore.shared.annotations.count)")
                lines.append("commentsBefore=\(ParagraphCommentStore.shared.items.count)")
                let url = try backup.export(password: "test-123")
                lines.append("fileEncrypted=\(BackupService.isEncryptedFile(at: url))")
                try await backup.restore(url: url, password: "test-123")
                lines.append("restoreOK=\(backup.lastRestoreSummary != nil)")
                lines.append("annotationsAfter=\(AnnotationStore.shared.annotations.count)")
                lines.append("commentsAfter=\(ParagraphCommentStore.shared.items.count)")
                lines.append("chapterCommentsAfter=\(ChapterCommentStore.shared.items.count)")
                lines.append("restoreSummary=\(backup.lastRestoreSummary?.localizedDescription ?? "nil")")
            } catch {
                lines.append("ERROR \(error.localizedDescription)")
            }
            let file = AppData.root.appendingPathComponent("backup-crypto-test.txt")
            try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            NSLog("[BackupCryptoTest] %@", lines.joined(separator: " | "))
        }
    }
}
#endif

#if DEBUG
@MainActor
enum CloudSyncDebugTest {
    static func run(settings: SettingsStore, books: BookStore) {
        let cloud = CloudSyncService.shared
        cloud.push(settings: settings.settings, books: books.books)
        let pullSummary = cloud.pull(into: settings, books: books)
        let lines = [
            "push=已执行",
            "pullSummary=\(pullSummary)",
            "paragraphCommentsAfter=\(ParagraphCommentStore.shared.items.count)",
            "chapterCommentsAfter=\(ChapterCommentStore.shared.items.count)",
            "driveAvailable=\(cloud.driveAvailable)",
            "kvsSettingsExists=\(NSUbiquitousKeyValueStore.default.data(forKey: "zhijian.settings.v1") != nil)",
            "kvsProgressExists=\(NSUbiquitousKeyValueStore.default.data(forKey: "zhijian.progress.v1") != nil)"
        ]
        try? lines.joined(separator: "\n").write(to: AppData.root.appendingPathComponent("cloud-test.txt"),
                                                 atomically: true, encoding: .utf8)
        NSLog("[CloudTest] %@", lines.joined(separator: " | "))
    }
}
#endif

#if DEBUG
@MainActor
enum CommentSyncDebugTest {
    static func run() {
        var lines: [String] = []
        let now = Date()
        let base = ParagraphComment(id: "test-conflict-1", bookId: "sync-test", chapterIndex: 0,
                                    paragraphIndex: 0, text: "旧版本", createdAt: now, updatedAt: now)
        _ = ParagraphCommentStore.shared.merge([base])
        var remote = base
        remote.text = "新版本"
        remote.updatedAt = now.addingTimeInterval(10)
        let result = ParagraphCommentStore.shared.merge([remote])
        let merged = ParagraphCommentStore.shared.comments(bookId: "sync-test", chapterIndex: 0, paragraphIndex: 0)
        lines.append("conflictNewerWins=\(merged.first?.text == "新版本")")
        lines.append("conflictCount=\(result.conflicts)")

        var deleted = remote
        deleted.deletedAt = now.addingTimeInterval(20)
        deleted.updatedAt = now.addingTimeInterval(20)
        let deleteResult = ParagraphCommentStore.shared.merge([deleted])
        let afterDelete = ParagraphCommentStore.shared.comments(bookId: "sync-test", chapterIndex: 0, paragraphIndex: 0)
        lines.append("tombstoneApplied=\(afterDelete.isEmpty)")
        lines.append("tombstoneCount=\(deleteResult.tombstones)")

        let pageBook = "page-test"
        for index in 0..<25 {
            ChapterCommentStore.shared.add(bookId: pageBook, chapterIndex: 0, chapterTitle: "分页",
                                           text: "评论 \(index)")
        }
        let firstPage = ChapterCommentStore.shared.comments(bookId: pageBook, chapterIndex: 0, limit: 10)
        let thirdPage = ChapterCommentStore.shared.comments(bookId: pageBook, chapterIndex: 0, limit: 10, offset: 20)
        lines.append("pageTotal=\(ChapterCommentStore.shared.totalCount(bookId: pageBook, chapterIndex: 0))")
        lines.append("page1=\(firstPage.count) page3=\(thirdPage.count)")

        let file = AppData.root.appendingPathComponent("comment-sync-test.txt")
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        NSLog("[CommentSyncTest] %@", lines.joined(separator: " | "))
    }
}
#endif

#if DEBUG
@MainActor
enum WebDAVCommentDebugTest {
    static func run(backup: BackupService) {
        Task { @MainActor in
            var lines: [String] = []
            let store = ChapterCommentStore.shared
            if store.count(bookId: "webdav-sync-test", chapterIndex: 0) == 0 {
                store.add(bookId: "webdav-sync-test", chapterIndex: 0, chapterTitle: "同步测试",
                          text: "来自本地的章末评论")
                ParagraphCommentStore.shared.add(bookId: "webdav-sync-test", chapterIndex: 0,
                                                 paragraphIndex: 0, text: "来自本地的段评")
            }
            let config = WebDAVConfig(id: "wd-test", name: "本地 WebDAV 测试",
                                      url: "http://127.0.0.1:8767/dav",
                                      username: "tester", password: "test",
                                      directory: "zhijian")
            do {
                let summary = try await backup.syncComments(to: config)
                lines.append("syncOK=true")
                lines.append("summary=\(summary.localizedDescription)")
                lines.append("localComments=\(ChapterCommentStore.shared.all().count)")
            } catch {
                lines.append("syncOK=false error=\(error.localizedDescription)")
            }
            let file = AppData.root.appendingPathComponent("webdav-comment-test.txt")
            try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            NSLog("[WebDAVCommentTest] %@", lines.joined(separator: " | "))
        }
    }
}
#endif

// MARK: - 真实书源回归（R2，extension）

@MainActor
extension AppEnvironment {
    /// 对已导入书源执行搜索 + 发现真实回归，返回报告行。
    func runSourceRegression() async -> [String] {
        var lines: [String] = []
        let enabled = engines.enabledSources()
        guard !enabled.isEmpty else {
            return ["无已启用书源（先导入书源再回归）"]
        }
        lines.append("书源数：\(enabled.count)")
        for source in enabled.prefix(3) {
            let pipeline = engines.makePipeline(source: source)
            var entry = source.bookSourceName
            if let status = pipeline.jsLibStatus { entry += " jsLib=\(status)" }
            if !(source.exploreUrl ?? "").isEmpty {
                do {
                    let categories = try await pipeline.exploreCategories()
                    entry += " 发现=\(categories.count)类"
                    if let first = categories.first {
                        let books = try await pipeline.explore(category: first, page: 1)
                        entry += " \(first.title)=\(books.count)本"
                    }
                } catch {
                    entry += " 发现✗=\(error.localizedDescription.prefix(40))"
                }
            }
            if !(source.searchUrl ?? "").isEmpty {
                do {
                    let books = try await pipeline.search("剑来", page: 1)
                    entry += " 搜索=\(books.count)本"
                } catch {
                    entry += " 搜索✗=\(error.localizedDescription.prefix(40))"
                }
            }
            lines.append(entry)
        }
        return lines
    }
}
