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
        case "booksource2":
            importSource(url)
        case "theme", "importtheme":
            importTheme(url)
        case "backup", "restore":
            importBackup(url)
        default:
            break
        }
    }

    /// `zhijian://source?url=https%3A%2F%2F...`、`yuedu://booksource/importonline?src=https://...`
    /// 或 `zhijian://source/https://...`
    private static func importSource(_ url: URL) {
        let raw = url.queryItem("src")
            ?? url.queryItem("url")
            ?? url.pathRemainder()
        guard let raw else { return }
        // 高危修复 1：SSRF / 强制解包——只允许 http/https，且非远程内容直接校验 JSON 再导入
        let text: String
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            guard let target = URL(string: raw), let scheme = target.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                notify("书源导入失败：仅支持 http/https 链接")
                return
            }
            // 导入前必须弹确认框（用户确认后才下载，避免无确认执行远程 JS）
            requestImportConfirmation(title: "导入书源", message: "将从 \(target.host ?? "") 下载并导入书源 JSON。确认要导入吗？") { confirmed in
                guard confirmed else { return }
                Task {
                    guard let fetched = try? await URLSession.shared.string(url: target.absoluteString),
                          !fetched.isEmpty else {
                        notify("书源导入失败：下载失败")
                        return
                    }
                    // 先校验是合法 JSON 再入库
                    guard AppEnvironment.shared.sources.isValidSourceJSON(fetched) else {
                        notify("书源导入失败：内容不是合法的书源 JSON")
                        return
                    }
                    try? AppEnvironment.shared.sources.importJSON(fetched)
                    notify("书源已导入")
                }
            }
        } else {
            text = raw.removingPercentEncoding ?? raw
            guard AppEnvironment.shared.sources.isValidSourceJSON(text) else {
                notify("书源导入失败：内容不是合法的书源 JSON")
                return
            }
            try? AppEnvironment.shared.sources.importJSON(text)
            notify("书源已导入")
        }
    }

    /// 导入确认框：通过通知让 RootView 弹出系统 alert
    private static func requestImportConfirmation(title: String, message: String, onConfirm: @escaping (Bool) -> Void) {
        let payload = ImportConfirmationRequest(title: title, message: message, onConfirm: onConfirm)
        NotificationCenter.default.post(name: .urlSchemeConfirmImport, object: nil, userInfo: ["request": payload])
    }

    private static func importTheme(_ url: URL) {
        guard let raw = url.queryItem("url") ?? url.pathRemainder() else { return }
        requestImportConfirmation(title: "导入主题包", message: "将从远程链接下载并导入主题包，确认吗？") { confirmed in
            guard confirmed else { return }
            Task {
                if raw.hasPrefix("http://") || raw.hasPrefix("https://"),
                   let target = URL(string: raw), let scheme = target.scheme?.lowercased(),
                   scheme == "http" || scheme == "https",
                   let data = try? await URLSession.shared.data(url: target.absoluteString) {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("import.zjtheme")
                    try? data.write(to: tmp)
                    _ = try? ReaderThemePackageStore.shared.importPackage(url: tmp)
                    notify("主题包已导入")
                }
            }
        }
    }

    private static func importBackup(_ url: URL) {
        guard let raw = url.queryItem("url") ?? url.pathRemainder() else { return }
        requestImportConfirmation(title: "下载备份", message: "将从远程链接下载备份文件，确认吗？") { confirmed in
            guard confirmed else { return }
            Task {
                if raw.hasPrefix("http://") || raw.hasPrefix("https://"),
                   let target = URL(string: raw), let scheme = target.scheme?.lowercased(),
                   scheme == "http" || scheme == "https",
                   let data = try? await URLSession.shared.data(url: target.absoluteString) {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("import.zjbk")
                    try? data.write(to: tmp)
                    notify("备份已下载，请在「备份与同步」恢复")
                }
            }
        }
    }

    private static func notify(_ text: String) {
        NotificationCenter.default.post(name: .urlSchemeImported, object: text)
    }
}

extension Notification.Name {
    static let urlSchemeImported = Notification.Name("zhijian.urlScheme.imported")
    static let urlSchemeConfirmImport = Notification.Name("zhijian.urlScheme.confirmImport")
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
        guard let target = URL(string: url), let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return "" }
        let (data, _) = try await data(from: target)
        return String(data: data, encoding: .utf8) ?? ""
    }
    func data(url: String) async throws -> Data {
        guard let target = URL(string: url), let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { throw URLError(.badURL) }
        let (data, _) = try await data(from: target)
        return data
    }
}

/// 导入确认请求（URLSchemeHandler 经通知投递，RootView 弹窗）
@MainActor
final class ImportConfirmationRequest: NSObject, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let onConfirm: (Bool) -> Void

    init(title: String, message: String, onConfirm: @escaping (Bool) -> Void) {
        self.title = title
        self.message = message
        self.onConfirm = onConfirm
    }
}
