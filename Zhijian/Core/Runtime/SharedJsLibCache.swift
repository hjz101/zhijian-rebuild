// SharedJsLibCache.swift — 书源 jsLib 共享脚本缓存（磁盘 + 内存）
import Foundation
import CryptoKit

final class SharedJsLibCache {
    static let shared = SharedJsLibCache()

    private let fm = FileManager.default
    private let root: URL
    private let ttl: TimeInterval = 24 * 3600

    private init() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("JsLib", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func load(url: String) -> String? {
        let file = root.appendingPathComponent(key(url) + ".js")
        if let attrs = try? fm.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < ttl,
           let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
            return text
        }
        guard let remote = URL(string: url) else { return nil }
        var request = URLRequest(url: remote)
        request.timeoutInterval = 15
        request.setValue("application/javascript, text/javascript, */*", forHTTPHeaderField: "Accept")
        let semaphore = DispatchSemaphore(value: 0)
        var body: String?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, !data.isEmpty {
                body = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let body, !body.isEmpty {
            try? body.write(to: file, atomically: true, encoding: .utf8)
            return body
        }
        // 网络失败时回退到过期缓存
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func clear() {
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func size() -> Int64 {
        var bytes: Int64 = 0
        for file in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
            bytes += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return bytes
    }

    private func key(_ url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
