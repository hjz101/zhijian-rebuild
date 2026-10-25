// URLSchemeHandler.swift — zhijian:// / qireader:// / yuedu:// 导入书源/主题/备份
import SwiftUI
import UIKit

@MainActor
enum URLSchemeHandler {
    static func handle(_ url: URL) {
        guard let host = url.host?.lowercased() else { return }
        switch host {
        case "source", "importsource", "booksource":
            importSource(url)
        case "theme", "importtheme":
            importTheme(url)
        case "backup", "restore":
            importBackup(url)
        default:
            break
        }
    }

    /// `zhijian://source?url=https%3A%2F%2F...` 或 `zhijian://source/https://...`
    private static func importSource(_ url: URL) {
        guard let raw = url.queryItem("url") ?? url.pathRemainder() else { return }
        Task {
            let text: String?
            if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
                text = try? await URLSession.shared.string(url: raw)
            } else {
                text = raw.removingPercentEncoding ?? raw
            }
            guard let text, !text.isEmpty else { return }
            try? AppEnvironment.shared.sources.importJSON(text)
            notify("书源已导入")
        }
    }

    private static func importTheme(_ url: URL) {
        guard let raw = url.queryItem("url") ?? url.pathRemainder() else { return }
        Task {
            if raw.hasPrefix("http://") || raw.hasPrefix("https://"),
               let data = try? await URLSession.shared.data(url: raw) {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("import.zjtheme")
                try? data.write(to: tmp)
                _ = try? ReaderThemePackageStore.shared.importPackage(url: tmp)
                notify("主题包已导入")
            }
        }
    }

    private static func importBackup(_ url: URL) {
        guard let raw = url.queryItem("url") ?? url.pathRemainder() else { return }
        Task {
            if raw.hasPrefix("http://") || raw.hasPrefix("https://"),
               let data = try? await URLSession.shared.data(url: raw) {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("import.zjbk")
                try? data.write(to: tmp)
                notify("备份已下载，请在「备份与同步」恢复")
            }
        }
    }

    private static func notify(_ text: String) {
        NotificationCenter.default.post(name: .urlSchemeImported, object: text)
    }
}

extension Notification.Name {
    static let urlSchemeImported = Notification.Name("zhijian.urlScheme.imported")
}

private extension URL {
    func queryItem(_ name: String) -> String? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first { $0.name == name }?.value
    }

    /// `scheme://host/rest` → 还原剩余路径
    func pathRemainder() -> String? {
        let path = path
        guard path.count > 1 else { return nil }
        return String(path.dropFirst())
    }
}

private extension URLSession {
    func string(url: String) async throws -> String {
        let (data, _) = try await data(from: URL(string: url)!)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf8)
            ?? ""
    }
    func data(url: String) async throws -> Data {
        let (data, _) = try await data(from: URL(string: url)!)
        return data
    }
}
