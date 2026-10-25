// ChapterTitleRenderer.swift — 章节标题 HTML 渲染 + 离屏快照缓存
import UIKit
import WebKit
import CryptoKit

enum ChapterTitleHTML {
    static func build(template: ChapterTitleTemplate, title: String, width: CGFloat, theme: ReaderTheme) -> String {
        let pageBackground = hexString(UIColor(theme.background))
        let scale = width / max(template.designWidth, 1)
        let height = max(48, width * template.heightRatio)
        let safeTitle = escape(title.isEmpty ? " " : title)
        let bg = template.backgroundHex.lowercased() == "#00000000" ? "transparent" : template.backgroundHex
        var body = ""
        for element in template.elements {
            let x = element.x * width
            let y = element.y * height
            let w = element.width * width
            let h = max(6, element.height * height)
            let fontSize = element.fontSize * scale
            let opacity = max(0, min(1, element.opacity))
            switch element.kind {
            case .text:
                body += """
                <div style="position:absolute;left:\(x)px;top:\(y)px;width:\(w)px;height:\(h)px;display:flex;align-items:center;justify-content:\(justify(element.alignment));opacity:\(opacity);">
                  <span style="font-family:-apple-system,'Songti SC',serif;font-size:\(fontSize)px;font-weight:\(element.fontWeight);color:\(element.colorHex);letter-spacing:\(element.letterSpacing * scale)px;text-align:\(element.alignment);width:100%;line-height:1.25;">\(safeTitle.replacingOccurrences(of: "__TEXT__", with: safeTitle))</span>
                </div>
                """
            case .line:
                body += """
                <div style="position:absolute;left:\(x)px;top:\(y)px;width:\(w)px;height:\(h)px;background:\(element.colorHex);opacity:\(opacity);border-radius:\(h / 2)px;"></div>
                """
            case .ornament:
                body += """
                <div style="position:absolute;left:\(x)px;top:\(y)px;width:\(w)px;height:\(h)px;display:flex;align-items:center;justify-content:\(justify(element.alignment));opacity:\(opacity);">
                  <span style="font-family:-apple-system,serif;font-size:\(fontSize)px;color:\(element.colorHex);letter-spacing:\(element.letterSpacing * scale)px;">\(escape(element.ornament))</span>
                </div>
                """
            case .image:
                if let base64 = element.imageBase64, !base64.isEmpty {
                    body += """
                    <div style="position:absolute;left:\(x)px;top:\(y)px;width:\(w)px;height:\(h)px;opacity:\(opacity);">
                      <img src="data:image/png;base64,\(base64)" style="width:100%;height:100%;object-fit:contain;" />
                    </div>
                    """
                }
            }
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
        html,body{margin:0;padding:0;background:\(pageBackground);}
        body{width:\(width)px;height:\(height)px;overflow:hidden;}
        .wrap{position:relative;width:\(width)px;height:\(height)px;background:\(bg == "transparent" ? pageBackground : bg);}
        </style></head><body><div class="wrap">\(body)</div></body></html>
        """
    }

    static func hexString(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }
        return "#FFFFFF"
    }

    private static func justify(_ alignment: String) -> String {
        switch alignment {
        case "left", "leading": return "flex-start"
        case "right", "trailing": return "flex-end"
        default: return "center"
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

@MainActor
final class ChapterTitleSnapshotService {
    static let shared = ChapterTitleSnapshotService()

    private var cache: [String: UIImage] = [:]
    private var order: [String] = []
    private let limit = 60
    private var webView: WKWebView?

    func snapshot(template: ChapterTitleTemplate, title: String, width: CGFloat,
                  theme: ReaderTheme = .paper) async -> UIImage? {
        let key = Self.key(template: template, title: title, width: width, theme: theme)
        if let hit = cache[key] { return hit }
        let html = ChapterTitleHTML.build(template: template, title: title, width: width, theme: theme)
        let height = max(48, width * template.heightRatio)
        guard let image = await render(html: html, size: CGSize(width: width, height: height)) else { return nil }
        cache[key] = image
        order.append(key)
        if order.count > limit {
            let removed = order.removeFirst()
            cache.removeValue(forKey: removed)
        }
        return image
    }

    func clearCache() {
        cache.removeAll()
        order.removeAll()
    }

    private func render(html: String, size: CGSize) async -> UIImage? {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let view = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        webView = view
        view.loadHTMLString(html, baseURL: nil)

        // 等一小段时间让布局完成（离屏 WebView 无导航回调可依赖）
        try? await Task.sleep(nanoseconds: 260_000_000)
        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = CGRect(origin: .zero, size: size)
        snapshotConfig.snapshotWidth = NSNumber(value: Double(size.width))
        return await withCheckedContinuation { continuation in
            view.takeSnapshot(with: snapshotConfig) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func key(template: ChapterTitleTemplate, title: String, width: CGFloat,
                            theme: ReaderTheme = .paper) -> String {
        let raw = "\(template.id)|\(Int(width.rounded()))|\(title)|\(template.elements.count)|\(theme.rawValue)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
