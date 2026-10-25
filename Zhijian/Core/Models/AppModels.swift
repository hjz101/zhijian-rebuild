// AppModels.swift — 应用层数据模型（书、章节、主题、TTS 源、备份清单…）
import Foundation
import SwiftUI

enum ReaderFontFamily: String, CaseIterable, Codable, Identifiable, Sendable {
    case songti, pingfang
    var id: String { rawValue }
    var name: String { self == .songti ? "宋体" : "苹方" }
}

enum ReaderTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case paper, ink, moss, parchment, nightTeal, plainWhite
    var id: String { rawValue }
    var name: String {
        switch self {
        case .paper: return "米宣纸"
        case .ink: return "深墨"
        case .moss: return "护眼绿"
        case .parchment: return "羊皮纸"
        case .nightTeal: return "暗夜青"
        case .plainWhite: return "素白"
        }
    }
    var background: Color {
        switch self {
        case .paper: return Color(hex: 0xF4EFE4)
        case .ink: return Color(hex: 0x12161C)
        case .moss: return Color(hex: 0xE6EDDF)
        case .parchment: return Color(hex: 0xF1E8D8)
        case .nightTeal: return Color(hex: 0x0E1B22)
        case .plainWhite: return Color(hex: 0xFBFCFD)
        }
    }
    var text: Color {
        switch self {
        case .paper: return Color(hex: 0x1F1C17)
        case .ink: return Color(hex: 0xC9C6BF)
        case .moss: return Color(hex: 0x26301F)
        case .parchment: return Color(hex: 0x3A2F22)
        case .nightTeal: return Color(hex: 0xC8DCE5)
        case .plainWhite: return Color(hex: 0x1B1E24)
        }
    }
    var secondary: Color {
        switch self {
        case .paper: return Color(hex: 0x6B6459)
        case .ink: return Color(hex: 0x8A8F99)
        case .moss: return Color(hex: 0x5E6B52)
        case .parchment: return Color(hex: 0x7C6F5C)
        case .nightTeal: return Color(hex: 0x6E8A98)
        case .plainWhite: return Color(hex: 0x5A6472)
        }
    }
    var backgroundHex: String {
        switch self {
        case .paper: return "#F4EFE4"
        case .ink: return "#12161C"
        case .moss: return "#E6EDDF"
        case .parchment: return "#F1E8D8"
        case .nightTeal: return "#0E1B22"
        case .plainWhite: return "#FBFCFD"
        }
    }
    var textHex: String {
        switch self {
        case .paper: return "#1F1C17"
        case .ink: return "#C9C6BF"
        case .moss: return "#26301F"
        case .parchment: return "#3A2F22"
        case .nightTeal: return "#C8DCE5"
        case .plainWhite: return "#1B1E24"
        }
    }
    var secondaryHex: String {
        switch self {
        case .paper: return "#6B6459"
        case .ink: return "#8A8F99"
        case .moss: return "#5E6B52"
        case .parchment: return "#7C6F5C"
        case .nightTeal: return "#6E8A98"
        case .plainWhite: return "#5A6472"
        }
    }
    var accentHex: String {
        switch self {
        case .paper: return "#C2552E"
        case .ink: return "#E8663D"
        case .moss: return "#4E8F86"
        case .parchment: return "#B08968"
        case .nightTeal: return "#4F9FBF"
        case .plainWhite: return "#3B82C4"
        }
    }
    var accent: Color {
        switch self {
        case .paper: return Color(hex: 0xC2552E)
        case .ink: return ZJ.accent
        case .moss: return Color(hex: 0x4E7A45)
        case .parchment: return Color(hex: 0xB08968)
        case .nightTeal: return Color(hex: 0x4F9FBF)
        case .plainWhite: return Color(hex: 0x3B82C4)
        }
    }
    /// 阅读器 chrome 色：控制栏/卡片背景（origo-x 的 surface/controlBar 思路）
    var surface: Color {
        switch self {
        case .paper: return Color(hex: 0xEDE5D6)
        case .ink: return Color(hex: 0x1D2530)
        case .moss: return Color(hex: 0xDCE6D4)
        case .parchment: return Color(hex: 0xE5D9C4)
        case .nightTeal: return Color(hex: 0x152630)
        case .plainWhite: return Color(hex: 0xEFF2F6)
        }
    }
    var surfaceHex: String {
        switch self {
        case .paper: return "#EDE5D6"
        case .ink: return "#1D2530"
        case .moss: return "#DCE6D4"
        case .parchment: return "#E5D9C4"
        case .nightTeal: return "#152630"
        case .plainWhite: return "#EFF2F6"
        }
    }
    var isDark: Bool { self == .ink || self == .nightTeal }
}

struct Book: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var author: String
    var coverURL: String?
    var intro: String?
    var sourceUrl: String?
    var bookUrl: String?
    var kind: String?
    var lastChapter: String?
    var totalChapters: Int
    var currentChapterIndex: Int
    var currentPageIndex: Int
    var currentScrollRatio: Double
    var addedAt: Date
    var lastReadAt: Date?
    var isLocal: Bool
    var fileName: String?
    var groupName: String?

    static func local(title: String, author: String, fileName: String) -> Book {
        Book(id: UUID().uuidString, title: title, author: author, coverURL: nil, intro: nil,
             sourceUrl: nil, bookUrl: nil, kind: nil, lastChapter: nil, totalChapters: 0,
             currentChapterIndex: 0, currentPageIndex: 0, currentScrollRatio: 0,
             addedAt: Date(), lastReadAt: nil, isLocal: true, fileName: fileName, groupName: nil)
    }

    static func remote(_ b: SourceBook, source: BookSource) -> Book {
        Book(id: UUID().uuidString, title: b.name, author: b.author, coverURL: b.coverUrl,
             intro: b.intro, sourceUrl: source.bookSourceUrl, bookUrl: b.bookUrl, kind: b.kind,
             lastChapter: b.lastChapter, totalChapters: 0, currentChapterIndex: 0,
             currentPageIndex: 0, currentScrollRatio: 0, addedAt: Date(), lastReadAt: nil,
             isLocal: false, fileName: nil, groupName: nil)
    }
}

struct Chapter: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var index: Int
    var title: String
    var url: String
    var isVip: Bool = false
    var isPay: Bool = false
    /// 卷名占位行（没有正文，阅读器不应加载）
    var isVolume: Bool = false
}

struct ChapterContent: Codable, Hashable, Sendable {
    var title: String
    var content: String
    var nextURL: String?
    var chapterURL: String?
}

struct HttpTTS: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var url: String
    var contentType: String?
    var concurrentRate: String?
    var enabledCookieJar: Bool?
    var loginUrl: String?
    var loginUi: String?
    var loginCheckJs: String?
    var header: String?
    var jsLib: String?
    var enabled: Bool?
}

struct WebDAVConfig: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var url: String
    var username: String
    var password: String
    var directory: String
}

struct BackupManifest: Codable, Hashable, Sendable {
    var version: Int
    var appVersion: String
    var createdAt: Date
    var deviceName: String
    var counts: [String: Int]
    var includesLocalBooks: Bool
    var categories: [String]
}

struct HighlightRule: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var pattern: String
    var colorHex: String = "#D9A441"
    var enabled: Bool = true
    var isRegex: Bool = false
}

struct ReadingSettings: Codable, Hashable, Sendable {
    var fontFamily: ReaderFontFamily = .songti
    /// 自定义字体 PostScript 名（为空时用 fontFamily）
    var customFontName: String = ""
    var fontSize: Double = 20
    var lineHeight: Double = 10
    var paragraphSpacing: Double = 10
    var horizontalPadding: Double = 22
    var theme: ReaderTheme = .paper
    var pageMode: PageMode = .paged
    /// iPad / 横屏双页（左右两栏）
    var twoPageEnabled: Bool = false
    /// 翻页动画
    var pageTurnAnimation: PageTurnAnimation = .slide
    /// 音量键翻页
    var volumeButtonPageTurn: Bool = false
    var showPageNumber: Bool = true
    var ttsRate: Double = 0.5

    // 章节标题设计器
    var chapterTitleAlignment: TitleAlignment = .center
    var chapterTitleScale: Double = 1.28
    var chapterTitleDecoration: TitleDecoration = .plain

    // 自动高亮规则
    var highlightRules: [HighlightRule] = []
    // 漫画纵向长图模式
    var mangaScrollMode: Bool = false
    /// P2-08：书源 HTTPS 优先
    var httpsFirst: Bool = true
    /// R2-04：超长章节在滚动模式下自动切分页（缓解长章卡顿）
    var longChapterAutoPaged: Bool = true
    /// THEME-V2：自定义阅读配色（启用时覆盖内置主题的画布/正文/强调/chrome 色）
    var customPalette: ReaderCustomPalette? = nil
    /// P2-09：段评气泡样式（颜色 hex / 圆角 / 图标）
    var bubbleColorHex: String = "#E8663D"
    var bubbleCornerRadius: Double = 16
    var bubbleIcon: String = "💬"

    enum PageMode: String, Codable, Sendable { case paged, scroll }
    enum PageTurnAnimation: String, Codable, Sendable, CaseIterable {
        case slide, curl, fade, none
        var name: String {
            switch self {
            case .slide: return "平移"
            case .curl: return "仿真翻页"
            case .fade: return "淡入"
            case .none: return "无动画"
            }
        }
    }
    enum TitleAlignment: String, Codable, Sendable, CaseIterable {
        case leading, center, trailing
        var name: String {
            switch self {
            case .leading: return "左对齐"
            case .center: return "居中"
            case .trailing: return "右对齐"
            }
        }
    }
    enum TitleDecoration: String, Codable, Sendable, CaseIterable {
        case plain, line, ornament
        var name: String {
            switch self {
            case .plain: return "无装饰"
            case .line: return "分隔线"
            case .ornament: return "花饰"
            }
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try container.decodeIfPresent(ReaderFontFamily.self, forKey: .fontFamily) ?? .songti
        customFontName = try container.decodeIfPresent(String.self, forKey: .customFontName) ?? ""
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 20
        lineHeight = try container.decodeIfPresent(Double.self, forKey: .lineHeight) ?? 10
        paragraphSpacing = try container.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? 10
        horizontalPadding = try container.decodeIfPresent(Double.self, forKey: .horizontalPadding) ?? 22
        theme = try container.decodeIfPresent(ReaderTheme.self, forKey: .theme) ?? .paper
        pageMode = try container.decodeIfPresent(PageMode.self, forKey: .pageMode) ?? .paged
        twoPageEnabled = try container.decodeIfPresent(Bool.self, forKey: .twoPageEnabled) ?? false
        pageTurnAnimation = try container.decodeIfPresent(PageTurnAnimation.self, forKey: .pageTurnAnimation) ?? .slide
        volumeButtonPageTurn = try container.decodeIfPresent(Bool.self, forKey: .volumeButtonPageTurn) ?? false
        showPageNumber = try container.decodeIfPresent(Bool.self, forKey: .showPageNumber) ?? true
        ttsRate = try container.decodeIfPresent(Double.self, forKey: .ttsRate) ?? 0.5
        chapterTitleAlignment = try container.decodeIfPresent(TitleAlignment.self, forKey: .chapterTitleAlignment) ?? .center
        chapterTitleScale = try container.decodeIfPresent(Double.self, forKey: .chapterTitleScale) ?? 1.28
        chapterTitleDecoration = try container.decodeIfPresent(TitleDecoration.self, forKey: .chapterTitleDecoration) ?? .plain
        highlightRules = try container.decodeIfPresent([HighlightRule].self, forKey: .highlightRules) ?? []
        mangaScrollMode = try container.decodeIfPresent(Bool.self, forKey: .mangaScrollMode) ?? false
        httpsFirst = try container.decodeIfPresent(Bool.self, forKey: .httpsFirst) ?? true
        longChapterAutoPaged = try container.decodeIfPresent(Bool.self, forKey: .longChapterAutoPaged) ?? true
        customPalette = try container.decodeIfPresent(ReaderCustomPalette.self, forKey: .customPalette)
        bubbleColorHex = try container.decodeIfPresent(String.self, forKey: .bubbleColorHex) ?? "#E8663D"
        bubbleCornerRadius = try container.decodeIfPresent(Double.self, forKey: .bubbleCornerRadius) ?? 16
        bubbleIcon = try container.decodeIfPresent(String.self, forKey: .bubbleIcon) ?? "💬"
    }
}
