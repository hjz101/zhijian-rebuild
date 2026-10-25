// JSBlock.swift — `<js>…</js>` / `@js:` 代码块解包（exploreUrl / loginUrl / jsLib 共用）
import Foundation

enum JSBlock {
    /// 去掉 `<js>` 与 `</js>`（或尾部多余 `>`）包装；`@js:` 前缀；其余原样返回。
    static func unwrap(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.hasPrefix("<js>") {
            var body = String(text.dropFirst(4))
            let bodyLower = body.lowercased()
            if bodyLower.hasSuffix("</js>") {
                body = String(body.dropLast(5))
            }
            return body
        }
        if lower.hasPrefix("@js:") {
            return String(text.dropFirst(4))
        }
        return text
    }

    /// 是否为 JS 代码块（`<js>` 或 `@js:`）。
    static func isScript(_ raw: String) -> Bool {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("<js>") || lower.hasPrefix("@js:")
    }
}
