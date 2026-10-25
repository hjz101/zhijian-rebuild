// ReaderTextBuilder.swift — 章节富文本构建（标题 / 正文 / 首行缩进 / 行距 / 段距）
//
// 排版参数只来自 ReadingSettings，颜色只来自 ReaderTheme。
// 分页缓存只依赖排版参数（颜色不影响断页），主题切换时只需重建 NSAttributedString。
import UIKit

enum ReaderTextBuilder {

    /// 影响断页结果的排版签名；主题、书签、TTS 等不参与。
    static func layoutSignature(_ settings: ReadingSettings) -> String {
        "\(settings.fontFamily.rawValue)|\(settings.fontSize)|\(settings.lineHeight)|\(settings.paragraphSpacing)|\(settings.chapterTitleAlignment.rawValue)|\(settings.chapterTitleScale)|\(settings.chapterTitleDecoration.rawValue)"
    }

    /// 把一章标题 + 正文构建成阅读排版用富文本。
    /// - 章节标题与正文首行重复时自动去重（部分书源的正文规则会带出标题）。
    /// - 空行合并为段距（由 paragraphSpacing 控制），每条非空行按一个自然段排版。
    static func build(
        title: String,
        body: String,
        settings: ReadingSettings,
        theme: ReaderTheme,
        titleImage: UIImage? = nil,
        pageWidth: CGFloat = 0
    ) -> NSAttributedString {
        let fontSize = CGFloat(settings.fontSize)
        let baseFont = ZJFont.reader(settings.fontFamily, size: fontSize)
        let textColor = UIColor(theme.text)
        let titleColor = UIColor(theme.text)

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        // 去掉正文开头与章节标题重复的一行。
        if !normalizedTitle.isEmpty,
           let firstIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let first = lines[firstIndex].trimmingCharacters(in: .whitespaces)
            if first == normalizedTitle || (first.count <= 60 && normalizedTitle.contains(first) && !first.isEmpty) {
                lines.removeSubrange(0...firstIndex)
            }
        }

        let result = NSMutableAttributedString()

        if let titleImage, pageWidth > 1 {
            // P1-03：HTML 标题模板快照，按页面宽度等比插入
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.paragraphSpacing = max(fontSize * 0.4, 8)
            paragraph.paragraphSpacingBefore = 0
            let scale = pageWidth / max(titleImage.size.width, 1)
            let attachment = NSTextAttachment()
            attachment.image = titleImage
            attachment.bounds = CGRect(x: 0, y: -4,
                                       width: pageWidth,
                                       height: titleImage.size.height * scale)
            let holder = NSMutableAttributedString(attachment: attachment)
            holder.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: holder.length))
            result.append(holder)
            result.append(NSAttributedString(string: "\n", attributes: [
                .font: UIFont.systemFont(ofSize: max(fontSize * 0.3, 6)),
                .paragraphStyle: paragraph
            ]))
        } else if !normalizedTitle.isEmpty {
            let titleParagraph = NSMutableParagraphStyle()
            switch settings.chapterTitleAlignment {
            case .leading: titleParagraph.alignment = .left
            case .center: titleParagraph.alignment = .center
            case .trailing: titleParagraph.alignment = .right
            }
            titleParagraph.lineSpacing = min(CGFloat(settings.lineHeight), 12)
            titleParagraph.paragraphSpacing = max(fontSize * 0.7, 12)
            titleParagraph.paragraphSpacingBefore = 0

            let titleFont: UIFont = {
                let size = fontSize * CGFloat(min(max(settings.chapterTitleScale, 1.0), 1.8))
                if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                    return UIFont(descriptor: descriptor, size: size)
                }
                return UIFont.systemFont(ofSize: size, weight: .semibold)
            }()

            result.append(NSAttributedString(string: normalizedTitle + "\n", attributes: [
                .font: titleFont,
                .foregroundColor: titleColor,
                .paragraphStyle: titleParagraph,
                .kern: 0.4
            ]))

            if settings.chapterTitleDecoration != .plain {
                let decorationParagraph = NSMutableParagraphStyle()
                decorationParagraph.alignment = titleParagraph.alignment
                decorationParagraph.paragraphSpacing = max(fontSize * 0.9, 14)
                decorationParagraph.lineSpacing = 0
                let decoration = settings.chapterTitleDecoration == .line ? "——————" : "·  ❖  ·"
                let decorationSize = max(fontSize * 0.62, 11)
                result.append(NSAttributedString(string: decoration + "\n", attributes: [
                    .font: UIFont.systemFont(ofSize: decorationSize, weight: .light),
                    .foregroundColor: UIColor(theme.accent).withAlphaComponent(0.75),
                    .paragraphStyle: decorationParagraph,
                    .kern: 3.0
                ]))
            }
        }

        let bodyStart = result.length
        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.alignment = .justified
        bodyParagraph.lineSpacing = CGFloat(settings.lineHeight)
        bodyParagraph.paragraphSpacing = CGFloat(settings.paragraphSpacing)
        bodyParagraph.firstLineHeadIndent = fontSize * 2
        bodyParagraph.headIndent = 0
        bodyParagraph.tailIndent = 0

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            result.append(NSAttributedString(string: line + "\n", attributes: [
                .font: baseFont,
                .foregroundColor: textColor,
                .paragraphStyle: bodyParagraph
            ]))
        }

        applyHighlightRules(settings.highlightRules, to: result, from: bodyStart)

        // 只有标题没有正文时补一个空行，保证有可渲染内容。
        if result.length == 0 {
            result.append(NSAttributedString(string: "\n", attributes: [
                .font: baseFont,
                .foregroundColor: textColor,
                .paragraphStyle: bodyParagraph
            ]))
        }
        return result
    }

    private static func color(hex: String, alpha: CGFloat) -> UIColor {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            return UIColor(red: 0.85, green: 0.64, blue: 0.25, alpha: alpha)
        }
        return UIColor(red: CGFloat((number >> 16) & 0xFF) / 255,
                       green: CGFloat((number >> 8) & 0xFF) / 255,
                       blue: CGFloat(number & 0xFF) / 255,
                       alpha: alpha)
    }

    private static func applyHighlightRules(_ rules: [HighlightRule], to text: NSMutableAttributedString, from start: Int) {
        guard !rules.isEmpty, start < text.length else { return }
        let fullRange = NSRange(location: start, length: text.length - start)
        for rule in rules where rule.enabled && !rule.pattern.isEmpty {
            let color = Self.color(hex: rule.colorHex, alpha: 0.42)
            if rule.isRegex {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
                for match in regex.matches(in: text.string, range: fullRange) where match.range.length > 0 {
                    text.addAttribute(.backgroundColor, value: color, range: match.range)
                }
            } else {
                var cursor = start
                while cursor < text.length {
                    let range = (text.string as NSString).range(of: rule.pattern, options: [.literal],
                                                              range: NSRange(location: cursor, length: text.length - cursor))
                    guard range.location != NSNotFound, range.length > 0 else { break }
                    text.addAttribute(.backgroundColor, value: color, range: range)
                    cursor = range.location + range.length
                }
            }
        }
    }
}
