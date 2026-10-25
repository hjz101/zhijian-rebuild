// ArchiveReader.swift — libarchive 读取 RAR/7z/zip（dlsym 弱链接，无需 SPM 依赖）
import Foundation

struct ArchiveEntryInfo: Sendable {
    var name: String
    var size: Int
}

enum ArchiveReaderError: LocalizedError {
    case unavailable
    case openFailed(String)
    case readFailed(String)
    case entryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "libarchive 不可用（当前系统缺少解码库）"
        case .openFailed(let detail): return "打开压缩包失败：\(detail)"
        case .readFailed(let detail): return "读取压缩包失败：\(detail)"
        case .entryNotFound(let name): return "压缩包内不存在：\(name)"
        }
    }
}

enum ArchiveReader {
    private typealias NewFn = @convention(c) () -> OpaquePointer?
    private typealias IntFn = @convention(c) (OpaquePointer?) -> Int32
    private typealias OpenMemoryFn = @convention(c) (OpaquePointer?, UnsafeRawPointer?, Int) -> Int32
    private typealias NextHeaderFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?) -> Int32
    private typealias PathnameFn = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    private typealias SizeFn = @convention(c) (OpaquePointer?) -> Int64
    private typealias ReadDataFn = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, Int) -> Int
    private typealias ErrorStringFn = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?

    private struct API {
        let new: NewFn
        let free: IntFn
        let supportFilter: IntFn
        let supportFormat: IntFn
        let openMemory: OpenMemoryFn
        let nextHeader: NextHeaderFn
        let pathname: PathnameFn
        let size: SizeFn
        let readData: ReadDataFn
        let errorString: ErrorStringFn
    }

    private static let api: API? = {
        let candidates = ["/usr/lib/libarchive.2.dylib", "/usr/lib/libarchive.dylib", "libarchive.2.dylib"]
        var handle: UnsafeMutableRawPointer?
        for path in candidates {
            handle = dlopen(path, RTLD_LAZY)
            if handle != nil { break }
        }
        guard let handle else { return nil }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard let new = symbol("archive_read_new", NewFn.self),
              let free = symbol("archive_read_free", IntFn.self),
              let filter = symbol("archive_read_support_filter_all", IntFn.self),
              let format = symbol("archive_read_support_format_all", IntFn.self),
              let open = symbol("archive_read_open_memory", OpenMemoryFn.self),
              let next = symbol("archive_read_next_header", NextHeaderFn.self),
              let path = symbol("archive_entry_pathname", PathnameFn.self),
              let size = symbol("archive_entry_size", SizeFn.self),
              let read = symbol("archive_read_data", ReadDataFn.self),
              let error = symbol("archive_error_string", ErrorStringFn.self) else {
            return nil
        }
        return API(new: new, free: free, supportFilter: filter, supportFormat: format,
                   openMemory: open, nextHeader: next, pathname: path, size: size,
                   readData: read, errorString: error)
    }()

    static var isAvailable: Bool { api != nil }

    static func list(data: Data) throws -> [ArchiveEntryInfo] {
        var items: [ArchiveEntryInfo] = []
        try scan(data: data) { entry, api, _ in
            guard let pointer = api.pathname(entry) else { return false }
            let name = String(cString: pointer)
            if !name.hasSuffix("/") {
                items.append(ArchiveEntryInfo(name: name, size: Int(api.size(entry))))
            }
            return false
        }
        return items
    }

    static func read(data: Data, entry target: String) throws -> Data {
        let normalizedTarget = normalize(target)
        var found: Data?
        try scan(data: data) { entry, api, archive in
            guard found == nil, let pointer = api.pathname(entry) else { return false }
            guard normalize(String(cString: pointer)) == normalizedTarget else { return false }
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { raw -> Int in
                    api.readData(archive, raw.baseAddress, raw.count)
                }
                if count <= 0 { break }
                output.append(buffer, count: count)
            }
            found = output
            return true
        }
        guard let found else { throw ArchiveReaderError.entryNotFound(target) }
        return found
    }

    static func extractAll(data: Data, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.standardizedFileURL
        try scan(data: data) { entry, api, archive in
            guard let pointer = api.pathname(entry) else { return false }
            let name = String(cString: pointer).replacingOccurrences(of: "\\", with: "/")
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."), !name.hasSuffix("/") else { return false }
            let target = root.appendingPathComponent(name).standardizedFileURL
            guard target.path.hasPrefix(root.path + "/") else { return false }
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { raw -> Int in
                    api.readData(archive, raw.baseAddress, raw.count)
                }
                if count <= 0 { break }
                output.append(buffer, count: count)
            }
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? output.write(to: target, options: .atomic)
            return false
        }
    }

    private static func normalize(_ name: String) -> String {
        var value = name.replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") { value.removeFirst(2) }
        return value
    }

    /// 遍历条目；闭包返回 true 时提前结束。
    private static func scan(data: Data, _ body: (OpaquePointer, API, OpaquePointer) throws -> Bool) throws {
        guard let api else { throw ArchiveReaderError.unavailable }
        let bytes = [UInt8](data)
        try bytes.withUnsafeBytes { raw in
            guard let archive = api.new() else { throw ArchiveReaderError.openFailed("archive_read_new") }
            defer { _ = api.free(archive) }
            _ = api.supportFilter(archive)
            _ = api.supportFormat(archive)
            guard api.openMemory(archive, raw.baseAddress, bytes.count) == 0 else {
                let message = api.errorString(archive).map { String(cString: $0) } ?? "unknown"
                throw ArchiveReaderError.openFailed(message)
            }
            var entry: OpaquePointer?
            while api.nextHeader(archive, &entry) == 0 {
                guard let entry else { continue }
                if try body(entry, api, archive) { return }
            }
        }
    }

}
