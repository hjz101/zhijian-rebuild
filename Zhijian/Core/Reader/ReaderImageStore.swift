// ReaderImageStore.swift — 正文图片下载 + 磁盘缓存 + 阅读器附件构建
import UIKit
import CryptoKit
import Combine

@MainActor
final class ReaderImageStore: ObservableObject {
    static let shared = ReaderImageStore()

    @Published private(set) var cacheBytes: Int64 = 0
    @Published private(set) var fileCount = 0

    private let fm = FileManager.default
    private let root: URL
    private var memory: [String: UIImage] = [:]
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("ReaderImages", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        refreshStats()
    }

    /// 同步内存命中（不含磁盘/下载），供排版线程使用。
    func cachedImage(_ url: String) -> UIImage? { memory[url] }

    func image(for url: String) async -> UIImage? {
        if let hit = memory[url] { return hit }
        let file = path(for: url)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory[url] = image
            return image
        }
        if let task = inflight[url] { return await task.value }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.download(url: url)
        }
        inflight[url] = task
        let image = await task.value
        inflight.removeValue(forKey: url)
        return image
    }

    /// 构建正文图片附件（等比缩放到最大宽度）。
    func attachment(url: String, maxWidth: CGFloat, placeholderText: String) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        if let image = memory[url] {
            attachment.image = image
            attachment.bounds = Self.bounds(for: image, maxWidth: maxWidth)
            return attachment
        }
        // 占位符（下载完成后由调用方重建）
        attachment.image = Self.placeholder(size: CGSize(width: maxWidth, height: maxWidth * 0.42),
                                            text: placeholderText)
        attachment.bounds = CGRect(x: 0, y: 0, width: maxWidth, height: maxWidth * 0.42)
        return attachment
    }

    func placeholderAttachment(maxWidth: CGFloat, height: CGFloat, text: String) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.image = Self.placeholder(size: CGSize(width: maxWidth, height: height), text: text)
        attachment.bounds = CGRect(x: 0, y: 0, width: maxWidth, height: height)
        return attachment
    }

    func refreshStats() {
        var bytes: Int64 = 0
        var files = 0
        for file in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
            files += 1
            bytes += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        cacheBytes = bytes
        fileCount = files
    }

    func clear() {
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        memory.removeAll()
        refreshStats()
    }

    var formattedSize: String { ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file) }

    // MARK: - 内部

    private func download(url: String) async -> UIImage? {
        guard let remote = URL(string: url) else { return nil }
        var request = URLRequest(url: remote)
        request.timeoutInterval = 20
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(HTTPClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://\(remote.host ?? "")/", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
        guard let image = UIImage(data: data), image.size.width > 1 else { return nil }
        try? data.write(to: path(for: url), options: .atomic)
        memory[url] = image
        refreshStats()
        return image
    }

    private func path(for url: String) -> URL {
        let digest = SHA256.hash(data: Data(url.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(name + ".img")
    }

    nonisolated static func bounds(for image: UIImage, maxWidth: CGFloat) -> CGRect {
        guard image.size.width > 1 else { return .zero }
        let scale = min(1, maxWidth / image.size.width)
        return CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
    }

    nonisolated static func placeholder(size: CGSize, text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(white: 0.5, alpha: 0.10).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(10, size.height * 0.16)),
                .foregroundColor: UIColor(white: 0.5, alpha: 0.8)
            ]
            let label = text as NSString
            let labelSize = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: (size.width - labelSize.width) / 2,
                                   y: (size.height - labelSize.height) / 2),
                       withAttributes: attributes)
        }
    }
}

extension NSAttributedString.Key {
    /// 正文图片附件的 URL（点击放大时读取）
    static let readerImageURL = NSAttributedString.Key("zhijian.readerImageURL")
}

/// 轻量门面：让非 MainActor 的排版代码同步读取已下载图片。
enum ReaderImageCache {
    @MainActor static var store: ReaderImageStore { .shared }

    /// 仅内存命中（不触发下载），供同步排版使用。
    nonisolated static func memoryImage(_ url: String) -> UIImage? {
        MainActor.assumeIsolated { ReaderImageStore.shared.cachedImage(url) }
    }
}
