// BackupModels.swift — 备份目的地 / 错误 / 结果模型
import Foundation

/// 备份目的地（本地文件或某个 WebDAV 配置）。
enum BackupDestination: Hashable, Identifiable, Sendable {
    case local
    case webDAV(configID: String)

    var id: String {
        switch self {
        case .local: return "local"
        case .webDAV(let configID): return "webdav:\(configID)"
        }
    }

    var title: String {
        switch self {
        case .local: return "本地文件"
        case .webDAV: return "WebDAV"
        }
    }
}

enum BackupError: LocalizedError {
    case notBackup
    case manifestMissing
    case unsupportedVersion(Int)
    case corrupt(String)
    case writeFailed(String)
    case noWebDAVConfig
    case emptyRemoteDirectory
    case encryptedNeedsPassword
    case wrongPassword
    case encryptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notBackup:
            return "不是有效的 .zjbk 备份（缺少 manifest.json）"
        case .manifestMissing:
            return "备份缺少 manifest.json"
        case .unsupportedVersion(let version):
            return "备份版本 \(version) 高于当前支持的版本"
        case .corrupt(let detail):
            return "备份文件损坏：\(detail)"
        case .writeFailed(let detail):
            return "写入备份失败：\(detail)"
        case .noWebDAVConfig:
            return "尚未配置 WebDAV"
        case .emptyRemoteDirectory:
            return "WebDAV 目录中没有 .zjbk 备份"
        case .encryptedNeedsPassword:
            return "该备份已加密，需要输入备份密码"
        case .wrongPassword:
            return "备份密码错误，或文件已损坏"
        case .encryptionFailed(let detail):
            return "备份加密失败：\(detail)"
        }
    }
}

/// 一次恢复的统计结果。
struct BackupRestoreSummary: Hashable, Sendable {
    var books: Int
    var sources: Int
    var ttsSources: Int
    var settingsRestored: Bool
    var annotations: Int = 0
    var paragraphComments: Int = 0
    var chapterComments: Int = 0
    var restoredAt: Date
    var remoteFileName: String?

    var localizedDescription: String {
        var parts: [String] = []
        parts.append("书架 \(books) 本")
        parts.append("书源 \(sources) 个")
        parts.append("TTS 源 \(ttsSources) 个")
        if settingsRestored { parts.append("阅读设置已恢复") }
        if annotations > 0 { parts.append("批注 \(annotations) 条") }
        if paragraphComments > 0 { parts.append("段评 \(paragraphComments) 条") }
        if chapterComments > 0 { parts.append("章末评论 \(chapterComments) 条") }
        return parts.joined(separator: " · ")
    }
}

/// WebDAV 目录中的备份条目。
struct RemoteBackupItem: Identifiable, Hashable, Sendable {
    var fileName: String
    var href: String
    var size: Int64?
    var modifiedAt: Date?
    var isDirectory: Bool

    var id: String { href }
}
