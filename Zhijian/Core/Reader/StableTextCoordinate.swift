// StableTextCoordinate.swift — 稳定文本坐标（P3-08）
// 用「前文锚点」把章节内的绝对偏移转成可跨排版复位的描述：
// anchor = 起点前最多 24 个字符，anchorOffset = 锚点内偏移。
import Foundation

enum StableTextCoordinate {
    static func makeAnchor(text: String, location: Int) -> (anchor: String, anchorOffset: Int)? {
        guard location > 0, location <= text.count else { return nil }
        let start = text.index(text.startIndex, offsetBy: max(0, location - 24), limitedBy: text.endIndex) ?? text.startIndex
        let end = text.index(text.startIndex, offsetBy: location, limitedBy: text.endIndex) ?? text.endIndex
        let anchor = String(text[start..<end])
        guard !anchor.isEmpty else { return nil }
        return (anchor, max(0, location - anchor.count))
    }

    static func resolve(anchor: String, offset: Int, in text: String) -> Int? {
        guard !anchor.isEmpty, let range = text.range(of: anchor) else { return nil }
        return text.distance(from: text.startIndex, to: range.lowerBound) + offset
    }

    static func resolveRange(location: Int, length: Int, in text: String) -> NSRange? {
        guard location >= 0, location + length <= text.count else { return nil }
        return NSRange(location: location, length: length)
    }
}
