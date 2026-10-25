// LocalizationManager.swift — 多语言（⑥ i18n 全量：中/英文案表 + 全局切换）
import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Sendable {
    case zh, en
    var name: String { self == .zh ? "简体中文" : "English" }
    var locale: Locale { self == .zh ? Locale(identifier: "zh-Hans") : Locale(identifier: "en") }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "zhijian.app.language") }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "zhijian.app.language") ?? "zh"
        language = AppLanguage(rawValue: raw) ?? .zh
    }

    /// 文案表：覆盖全部高频 UI 文案（页面标题/按钮/设置项/提示）。
    static func tr(_ key: String) -> String {
        let zh: [String: String] = [
            // 底部 Tab
            "tab.shelf": "书架", "tab.stats": "统计", "tab.settings": "设置", "tab.discover": "发现",
            // 书架
            "shelf.empty": "书架空空如也", "shelf.searchHint": "搜索书源或导入本地文件",
            "shelf.continue": "继续", "shelf.recent": "最近阅读", "shelf.all": "全部",
            "shelf.grid": "网格", "shelf.list": "列表", "shelf.group": "分组",
            // 统计
            "stats.title": "阅读统计", "stats.today": "今日", "stats.week": "本周",
            "stats.streak": "连续", "stats.dailyGoal": "每日目标", "stats.trend30": "近 30 日",
            "stats.total": "总时长", "stats.avgDay": "日均", "stats.activeDays": "活跃天数",
            "stats.books": "阅读书籍",
            // 设置
            "settings.title": "设置", "settings.reader": "阅读", "settings.tts": "朗读",
            "settings.backup": "备份与同步", "settings.sources": "书源", "settings.appearance": "外观",
            "settings.language": "语言 / Language", "settings.about": "关于",
            // 阅读器
            "reader.settings": "阅读设置", "reader.catalog": "目录", "reader.bookmark": "书签",
            "reader.note": "笔记", "reader.menu": "更多", "reader.changeSource": "换源",
            "reader.paged": "分页", "reader.scroll": "滚动", "reader.theme": "主题",
            "reader.custom": "自定义", "reader.font": "字体", "reader.highlight": "高亮",
            "reader.bubble": "段评气泡", "reader.traditional": "正文繁体",
            "reader.autoPaged": "长章自动分页",
            // 来源/发现
            "sources.title": "书源", "sources.import": "导入", "sources.export": "导出",
            "sources.test": "体检", "sources.edit": "编辑", "sources.group": "分组",
            "discover.title": "发现", "discover.loading": "正在加载发现页…",
            "discover.empty": "暂无发现内容", "discover.failed": "发现页加载失败",
            // TTS
            "tts.title": "朗读", "tts.play": "播放", "tts.pause": "暂停", "tts.stop": "停止",
            "tts.rate": "语速", "tts.sleep": "睡眠定时", "tts.roles": "多角色",
            // 备份/同步
            "backup.title": "备份", "backup.export": "导出备份", "backup.restore": "恢复",
            "backup.webdav": "WebDAV", "backup.icloud": "iCloud", "backup.auto": "自动备份",
            "backup.localBooks": "包含本地书正文",
            // 通用
            "common.cancel": "取消", "common.done": "完成", "common.save": "保存",
            "common.delete": "删除", "common.confirm": "确定", "common.search": "搜索",
            "common.loading": "加载中…", "common.failed": "失败", "common.import": "导入",
            "common.share": "分享", "common.copy": "复制", "common.close": "关闭",
            // 低频补充
            "backup.exportNow": "立即备份", "backup.lastTime": "上次备份", "backup.frequency": "备份频率",
            "backup.onExit": "退出时", "backup.daily": "每天", "backup.weekly": "每周",
            "backup.mirror": "镜像备份目录到 WebDAV（增量）",
            "sources.health": "书源体检", "sources.batch": "批量测试", "sources.diagnose": "诊断",
            "sources.duplicate": "去重", "sources.importURL": "从 URL 导入", "sources.clipboard": "从剪贴板导入",
            "tts.source": "TTS 源", "tts.voice": "音色", "tts.pitch": "音高", "tts.test": "试听",
            "tts.aiRoles": "AI 角色识别", "tts.llmKey": "API Key",
            "reader.titleDesigner": "章节标题设计器", "reader.background": "阅读背景",
            "reader.themePackages": "主题包", "reader.fonts": "字体管理", "reader.highlightRules": "高亮规则",
            "reader.comments": "评论", "reader.paragraph": "段评", "reader.chapterComments": "章末评论",
            "files.title": "文件管理", "files.import": "导入文件", "files.rename": "重命名",
            "files.move": "移动到…", "files.copy": "复制到…", "files.delete": "删除",
            "stats.year": "年度目标", "stats.day": "今日卡", "stats.booksRead": "书籍统计",
            "stats.minutes": "分钟 / 分", "stats.heatmap": "热力图",
            "reader.themePackage": "阅读主题包", "reader.bgImage": "阅读背景图",
            "cache.title": "缓存管理", "cache.desc": "目录缓存 24 小时自动刷新；正文按 200 MB LRU 上限自动清理。断网可读已缓存章节。",
            "backup.done": "备份已生成", "backup.mkcol": "目录不存在时上传会自动 MKCOL 创建，支持多级目录。",
            "fonts.title": "字体管理", "fonts.desc": "字体文件保存在 Application Support/Zhijian/Fonts，切换字体后会重新分页但保留阅读进度。",
            "tts.rolesDesc": "朗读一章后自动识别角色，并按角色分配不同语音",
            "sources.address": "书源地址", "batch.hint": "设置关键词后点击「开始批量测试」"
        ]
        let en: [String: String] = [
            "tab.shelf": "Shelf", "tab.stats": "Stats", "tab.settings": "Settings", "tab.discover": "Discover",
            "shelf.empty": "Your shelf is empty", "shelf.searchHint": "Search sources or import local files",
            "shelf.continue": "Continue", "shelf.recent": "Recent", "shelf.all": "All",
            "shelf.grid": "Grid", "shelf.list": "List", "shelf.group": "Group",
            "stats.title": "Reading Stats", "stats.today": "Today", "stats.week": "Week",
            "stats.streak": "Streak", "stats.dailyGoal": "Daily Goal", "stats.trend30": "Last 30 Days",
            "stats.total": "Total", "stats.avgDay": "Daily Avg", "stats.activeDays": "Active Days",
            "stats.books": "Books Read",
            "settings.title": "Settings", "settings.reader": "Reader", "settings.tts": "TTS",
            "settings.backup": "Backup & Sync", "settings.sources": "Sources", "settings.appearance": "Appearance",
            "settings.language": "Language", "settings.about": "About",
            "reader.settings": "Reader Settings", "reader.catalog": "Catalog", "reader.bookmark": "Bookmarks",
            "reader.note": "Notes", "reader.menu": "More", "reader.changeSource": "Change Source",
            "reader.paged": "Paged", "reader.scroll": "Scroll", "reader.theme": "Theme",
            "reader.custom": "Custom", "reader.font": "Font", "reader.highlight": "Highlight",
            "reader.bubble": "Comment Bubble", "reader.traditional": "Traditional Chinese",
            "reader.autoPaged": "Auto-paged Long Chapters",
            "sources.title": "Sources", "sources.import": "Import", "sources.export": "Export",
            "sources.test": "Test", "sources.edit": "Edit", "sources.group": "Group",
            "discover.title": "Discover", "discover.loading": "Loading discover…",
            "discover.empty": "No discover content", "discover.failed": "Discover failed to load",
            "tts.title": "TTS", "tts.play": "Play", "tts.pause": "Pause", "tts.stop": "Stop",
            "tts.rate": "Rate", "tts.sleep": "Sleep Timer", "tts.roles": "Roles",
            "backup.title": "Backup", "backup.export": "Export Backup", "backup.restore": "Restore",
            "backup.webdav": "WebDAV", "backup.icloud": "iCloud", "backup.auto": "Auto Backup",
            "backup.localBooks": "Include Local Book Content",
            "common.cancel": "Cancel", "common.done": "Done", "common.save": "Save",
            "common.delete": "Delete", "common.confirm": "OK", "common.search": "Search",
            "common.loading": "Loading…", "common.failed": "Failed", "common.import": "Import",
            "common.share": "Share", "common.copy": "Copy", "common.close": "Close",
            "backup.exportNow": "Backup Now", "backup.lastTime": "Last Backup", "backup.frequency": "Frequency",
            "backup.onExit": "On Exit", "backup.daily": "Daily", "backup.weekly": "Weekly",
            "backup.mirror": "Mirror to WebDAV (incremental)",
            "sources.health": "Source Health", "sources.batch": "Batch Test", "sources.diagnose": "Diagnose",
            "sources.duplicate": "Deduplicate", "sources.importURL": "Import from URL", "sources.clipboard": "Import from Clipboard",
            "tts.source": "TTS Source", "tts.voice": "Voice", "tts.pitch": "Pitch", "tts.test": "Preview",
            "tts.aiRoles": "AI Role Detection", "tts.llmKey": "API Key",
            "reader.titleDesigner": "Chapter Title Designer", "reader.background": "Reading Background",
            "reader.themePackages": "Theme Packages", "reader.fonts": "Fonts", "reader.highlightRules": "Highlight Rules",
            "reader.comments": "Comments", "reader.paragraph": "Paragraph", "reader.chapterComments": "Chapter Comments",
            "files.title": "Files", "files.import": "Import Files", "files.rename": "Rename",
            "files.move": "Move to…", "files.copy": "Copy to…", "files.delete": "Delete",
            "stats.year": "Yearly Goal", "stats.day": "Today Card", "stats.booksRead": "Book Stats",
            "stats.minutes": "Minutes", "stats.heatmap": "Heatmap",
            "reader.themePackage": "Theme Package", "reader.bgImage": "Background Image",
            "cache.title": "Cache", "cache.desc": "Chapter cache refreshes every 24h; body capped at 200MB LRU. Cached chapters readable offline.",
            "backup.done": "Backup Created", "backup.mkcol": "MKCOL auto-creates missing directories, multi-level supported.",
            "fonts.title": "Fonts", "fonts.desc": "Fonts stored in Application Support/Zhijian/Fonts. Repaginates on switch, progress kept.",
            "tts.rolesDesc": "Auto-detect roles after reading a chapter and assign voices",
            "sources.address": "Source URL", "batch.hint": "Set a keyword and tap Start Batch Test"
        ]
        let table = shared.language == .zh ? zh : en
        return table[key] ?? key
    }
}
