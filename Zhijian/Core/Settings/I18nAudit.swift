// I18nAudit.swift — i18n 深度校验：扫描硬编码中文文案，输出未覆盖报告
import Foundation

@MainActor
enum I18nAudit {
    /// 扫描所有 Swift 源文件里的中文字符串字面量，与文案表比对。
    static func run() -> [String] {
        var findings: [String] = []
        guard let root = Bundle.main.resourceURL?.deletingLastPathComponent() else { return ["无法定位源码目录"] }
        let srcRoot = root.appendingPathComponent("Zhijian")
        guard let enumerator = FileManager.default.enumerator(at: srcRoot,
                                                              includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else {
            return ["Zhijian 目录不存在（Audit 在模拟器运行）"]
        }
        // 文案表已知中文值
        let knownValues = Set(["书架", "统计", "设置", "发现", "继续", "最近阅读", "阅读统计",
                               "今日", "本周", "连续", "近 30 日", "备份", "导入", "导出", "体检",
                               "取消", "完成", "保存", "删除", "搜索", "加载中…", "失败", "分享",
                               "复制", "关闭", "朗读", "播放", "暂停", "停止", "语速", "睡眠定时",
                               "多角色", "文件", "重命名", "移动到…", "复制到…", "阅读设置",
                               "目录", "书签", "笔记", "换源", "分页", "滚动", "主题", "自定义",
                               "字体", "高亮", "段评气泡", "正文繁体", "长章自动分页",
                               "阅读主题包", "阅读背景图", "缓存管理", "备份已生成", "字体管理",
                               "书源地址", "语言 / Language", "外观", "网络代理", "文件管理",
                               "立即备份", "备份频率", "退出时", "每天", "每周", "镜像备份目录到 WebDAV（增量）",
                               "书源体检", "批量测试", "诊断", "去重", "试听", "分钟 / 分"])
        guard let pattern = try? NSRegularExpression(pattern: #""([^"\\]|\\.)*[\u{4E00}-\u{9FFF}]+([^"\\]|\\.)*""#) else { return ["正则初始化失败"] }
        var fileCount = 0
        var hitCount = 0
        while let entry = enumerator.nextObject() as? URL {
            guard entry.pathExtension == "swift" else { continue }
            fileCount += 1
            guard let content = try? String(contentsOf: entry, encoding: .utf8) else { continue }
            let range = NSRange(location: 0, length: (content as NSString).length)
            let matches = pattern.matches(in: content, options: [], range: range)
            for match in matches {
                guard let swiftRange = Range(match.range, in: content) else { continue }
                let literal = String(content[swiftRange])
                // 跳过 tr() 参数内与注释
                let before = content[..<swiftRange.lowerBound].suffix(40)
                if before.contains("tr(") || before.contains("//") || before.contains("tr(\"") { continue }
                let trimmed = literal.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if knownValues.contains(trimmed) { continue }
                hitCount += 1
                if hitCount <= 60 {
                    findings.append("\(entry.lastPathComponent): \(trimmed)")
                }
            }
        }
        findings.insert("扫描文件 \(fileCount) 个，未覆盖中文文案 \(hitCount) 处（显示前 60）", at: 0)
        return findings
    }
}
