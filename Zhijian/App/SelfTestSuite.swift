// SelfTestSuite.swift — 统一回归自检（-selfTestSuite）
// 覆盖纯函数逻辑：JSBlock / PseudoURL / 替换 / 目录 / 加密 / 镜像 diff / 稳定坐标 / 段切分 / TOC 数字。
import Foundation

@MainActor
enum SelfTestSuite {
    static func run() -> String {
        var failures: [String] = []
        var passed = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition { passed += 1 }
            else { failures.append("\(name)\(detail.isEmpty ? "" : "：\(detail)")") }
        }

        // 1) JSBlock 解包
        check("JSBlock-js-end", JSBlock.unwrap("<js>\nlet a=1;\n</js>") == "\nlet a=1;\n")
        check("JSBlock-atjs", JSBlock.unwrap("@js:let a=1") == "let a=1")
        check("JSBlock-plain", JSBlock.unwrap("let a=1") == "let a=1")
        check("JSBlock-isScript", JSBlock.isScript("<js>x</js>") && !JSBlock.isScript("plain"))

        // 2) PseudoURL
        check("PseudoURL-base64", SourcePipeline.PseudoURL.looksLikeHex("aabbccddeeff0011"))
        check("PseudoURL-payload",
              SourcePipeline.PseudoURL.payload("data:detailsUrl;base64,eyJhIjoxfQ==") == "7b2261223a317d")
        check("PseudoURL-isData", SourcePipeline.PseudoURL.isData("data:x;base64,abc"))

        // 3) ReplaceRuleEngine
        let replaceResult = ReplaceRuleEngine.apply([
            ReplaceRule(name: "删广告", pattern: "【广告】.*", replacement: "", isRegex: true, scope: .content)
        ], to: "正文【广告】点击", scope: .content)
        check("ReplaceRule-content", replaceResult.text == "正文", replaceResult.text)
        let titleResult = ReplaceRuleEngine.apply([
            ReplaceRule(name: "章号", pattern: "^第\\d+章\\s*", replacement: "", isRegex: true, scope: .title)
        ], to: "第12章 山雨", scope: .title)
        check("ReplaceRule-title", titleResult.text == "山雨", titleResult.text)

        // 4) ChapterRuleEngine（≥3 章才排序，<3 章保持原序）
        let toc = [
            SourceChapter(index: 0, title: "第3章 风起", url: "3", updateTime: "", isVolume: false),
            SourceChapter(index: 1, title: "第1章 入山", url: "1", updateTime: "", isVolume: false),
            SourceChapter(index: 2, title: "第2章 书庐", url: "2", updateTime: "", isVolume: false),
            SourceChapter(index: 3, title: "第2章 书庐", url: "2", updateTime: "", isVolume: false),
            SourceChapter(index: 4, title: "", url: "e", updateTime: "", isVolume: false)
        ]
        var cfg = ChapterRuleConfig()
        let tocResult = ChapterRuleEngine.apply(toc, config: cfg)
        check("ChapterRule-dedup-empty", tocResult.chapters.count == 3, "count=\(tocResult.chapters.count)")
        check("ChapterRule-sorted", tocResult.chapters.map(\.title) == ["第1章 入山", "第2章 书庐", "第3章 风起"],
              "titles=\(tocResult.chapters.map(\.title))")

        // 5) BackupCrypto 往返
        if let encrypted = try? BackupCrypto.encrypt(Data("备份-测试".utf8), password: "pw-123"),
           let decrypted = try? BackupCrypto.decrypt(encrypted, password: "pw-123") {
            check("BackupCrypto-roundtrip", decrypted == Data("备份-测试".utf8))
        } else {
            check("BackupCrypto-roundtrip", false, "加密/解密失败")
        }

        // 6) WebDAVMirror.diff
        let now = Date()
        let diff = WebDAVMirrorService.diff(
            local: ["a": (100, now), "b": (200, now)],
            remote: ["a": (100, now), "c": (300, now.addingTimeInterval(7200))]
        )
        check("Mirror-unchanged", diff.unchanged == ["a"])
        check("Mirror-upload", diff.upload == ["b"])
        check("Mirror-delete", diff.delete == ["c"])

        // 7) StableTextCoordinate
        let anchor = StableTextCoordinate.makeAnchor(text: "一二三四五六七八九十", location: 6)
        check("Stable-anchor", anchor?.anchor == "一二三四五六", "\(anchor?.anchor ?? "nil")")
        if let a = anchor, let resolved = StableTextCoordinate.resolve(anchor: a.anchor, offset: a.anchorOffset, in: "前缀一二三四五六七八九十") {
            check("Stable-resolve", resolved == 2 + 6, "resolved=\(resolved)")
        } else {
            check("Stable-resolve", false, "resolve 失败")
        }

        // 8) TTSScriptSegmenter
        let segments = TTSScriptSegmenter.segments("阿禾说：“山雾散了。”", maxLength: 30, splitRoles: true)
        check("TTS-segment-roles", segments.contains { $0.characterName != nil }, "roles=\(segments.map { $0.characterName ?? "-" })")

        // 9) parseTOCNumber
        check("TOCNum-arabic", SourcePipeline.parseTOCNumber("12") == 12)
        check("TOCNum-chinese", SourcePipeline.parseTOCNumber("十二") == 12)

        let summary = "自检完成：通过 \(passed) 项，失败 \(failures.count) 项"
        let lines = [summary] + (failures.isEmpty ? ["全部通过 ✅"] : failures.map { "✗ \($0)" })
        return lines.joined(separator: "\n")
    }
}
