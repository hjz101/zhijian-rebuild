// WebDAVMirrorService.swift — 目录增量镜像（PROPFIND 比对大小/时间，只传变化文件）
import Foundation

struct WebDAVMirrorResult: Sendable {
    var uploaded = 0
    var unchanged = 0
    var conflicts = 0
    var deleted = 0
    var failed: [String] = []

    var summary: String {
        var parts: [String] = []
        if uploaded > 0 { parts.append("上传 \(uploaded)") }
        if unchanged > 0 { parts.append("跳过 \(unchanged)（无变化）") }
        if conflicts > 0 { parts.append("冲突 \(conflicts)（远端更新，未覆盖）") }
        if deleted > 0 { parts.append("删除 \(deleted)（远端多余）") }
        if !failed.isEmpty { parts.append("失败 \(failed.count)") }
        return parts.isEmpty ? "无变化" : parts.joined(separator: " · ")
    }
}

/// 目录增量镜像：递归 PROPFIND 远端，比对本地文件（大小 + 修改时间），
/// 仅上传新增/变化文件；可选删除远端多余文件；冲突（远端较新且大小不同）跳过并提示。
@MainActor
enum WebDAVMirrorService {
    private static let fm = FileManager.default

    static func mirror(localRoot: URL, config: WebDAVConfig, deleteRemote: Bool = false) async throws -> WebDAVMirrorResult {
        let client = WebDAVClient(config: config)
        var result = WebDAVMirrorResult()

        // 1) 本地文件清单 [相对路径: (size, mtime)]
        var localFiles: [String: (size: Int64, mtime: Date)] = [:]
        collectLocal(root: localRoot, prefix: "", into: &localFiles)

        // 2) 远端文件清单
        let remoteRoot = try clientDirectoryURL(config)
        var remoteFiles: [String: RemoteBackupItem] = [:]
        try await collectRemote(root: remoteRoot, client: client, prefix: "", into: &remoteFiles)

        // 3) 比对 + 上传
        for (relativePath, local) in localFiles.sorted(by: { $0.key < $1.key }) {
            if let remote = remoteFiles[relativePath] {
                if let remoteSize = remote.size, remoteSize == local.size {
                    result.unchanged += 1
                    continue
                }
                // 冲突：远端存在且大小不同，且远端修改时间比本地新 → 跳过（保护远端）
                if let remoteDate = remote.modifiedAt,
                   remoteDate.timeIntervalSince(local.mtime) > 60,
                   remote.size != nil {
                    result.conflicts += 1
                    continue
                }
            }
            let localURL = localRoot.appendingPathComponent(relativePath)
            do {
                _ = try await client.putFile(localURL: localURL, remoteRelativePath: relativePath)
                result.uploaded += 1
            } catch {
                result.failed.append(relativePath)
            }
        }

        // 4) 可选：删除远端多余文件
        if deleteRemote {
            let localSet = Set(localFiles.keys)
            for (relativePath, remote) in remoteFiles.sorted(by: { $0.key < $1.key })
                where !remote.isDirectory && !localSet.contains(relativePath) {
                do {
                    try await client.deleteRemoteFile(remoteRelativePath: relativePath)
                    result.deleted += 1
                } catch {
                    result.failed.append("del:\(relativePath)")
                }
            }
        }

        return result
    }

    /// 纯 diff（不联网），供自检与预览。冲突 = 远端存在、大小不同且远端比本地新。
    static func diff(local: [String: (size: Int64, mtime: Date)],
                     remote: [String: (size: Int64?, mtime: Date?)]) -> (upload: [String], unchanged: [String], conflicts: [String], delete: [String]) {
        var upload: [String] = []
        var unchanged: [String] = []
        var conflicts: [String] = []
        for (path, localItem) in local.sorted(by: { $0.key < $1.key }) {
            if let r = remote[path] {
                if let rSize = r.size, rSize == localItem.size {
                    unchanged.append(path)
                } else if let rDate = r.mtime, rDate.timeIntervalSince(localItem.mtime) > 60 {
                    conflicts.append(path)
                } else {
                    upload.append(path)
                }
            } else {
                upload.append(path)
            }
        }
        let localSet = Set(local.keys)
        let delete = remote.keys.filter { !localSet.contains($0) && $0 != "" }.sorted()
        return (upload, unchanged, conflicts, delete)
    }

    // MARK: - 内部

    private static func clientDirectoryURL(_ config: WebDAVConfig) throws -> URL {
        guard !config.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let base = URL(string: config.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw WebDAVError.invalidURL(config.url)
        }
        var url = base
        for segment in config.directory.split(separator: "/").map(String.init) where !segment.isEmpty {
            url.appendPathComponent(segment)
        }
        return url
    }

    private static func collectLocal(root: URL, prefix: String, into files: inout [String: (size: Int64, mtime: Date)]) {
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else { return }
        for item in items {
            let name = item.lastPathComponent
            let rel = prefix.isEmpty ? name : "\(prefix)/\(name)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                collectLocal(root: item, prefix: rel, into: &files)
            } else {
                let size = Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                let mtime = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                files[rel] = (size, mtime)
            }
        }
    }

    private static func collectRemote(root: URL, client: WebDAVClient, prefix: String, into files: inout [String: RemoteBackupItem]) async throws {
        let items = try await client.listDirectoryContents(root)
        for item in items where !item.href.hasSuffix(root.absoluteString) {
            let name = item.fileName
            guard !name.isEmpty else { continue }
            let rel = prefix.isEmpty ? name : "\(prefix)/\(name)"
            if item.isDirectory {
                var child = root
                child.appendPathComponent(name)
                try await collectRemote(root: child, client: client, prefix: rel, into: &files)
            } else {
                files[rel] = item
            }
        }
    }
}
