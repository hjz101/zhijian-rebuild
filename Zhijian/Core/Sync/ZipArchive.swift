// ZipArchive.swift — 极简 ZIP 写入/读取（store 不压缩），复用旧工程 ZipWriter/ZipReader
//
// 备份容器 `.zjbk` = 标准 ZIP（store 方式）：根 manifest.json + 各分类 JSON。
// 读取兼容 stored / deflate（Compression 框架），可读取旧工程与系统生成的 ZIP。
import Foundation
import Compression

struct ZipWriter {
    private var entries: [(name: String, data: Data, crc: UInt32)] = []

    mutating func add(_ data: Data, name: String) {
        entries.append((name, data, CRC32.checksum(data)))
    }

    mutating func addText(_ text: String, name: String) {
        add(Data(text.utf8), name: name)
    }

    /// 生成 zip 数据（store 方法，兼容系统解压/我们的 ZipReader）。
    func build() -> Data {
        var out = Data()
        var central = Data()
        var offsets: [Int] = []
        let (dosTime, dosDate) = Self.dosTimestamp(Date())

        for entry in entries {
            offsets.append(out.count)
            let nameData = Data(entry.name.utf8)
            out.append(le32(0x04034b50))
            out.append(le16(20))            // version needed
            out.append(le16(0x0800))        // UTF-8 flag
            out.append(le16(0))             // method: store
            out.append(le16(dosTime))
            out.append(le16(dosDate))
            out.append(le32(entry.crc))
            out.append(le32(UInt32(entry.data.count)))
            out.append(le32(UInt32(entry.data.count)))
            out.append(le16(UInt16(nameData.count)))
            out.append(le16(0))             // extra len
            out.append(nameData)
            out.append(entry.data)
        }

        for (index, entry) in entries.enumerated() {
            let nameData = Data(entry.name.utf8)
            central.append(le32(0x02014b50))
            central.append(le16(20))        // version made by
            central.append(le16(20))        // version needed
            central.append(le16(0x0800))
            central.append(le16(0))
            central.append(le16(dosTime))
            central.append(le16(dosDate))
            central.append(le32(entry.crc))
            central.append(le32(UInt32(entry.data.count)))
            central.append(le32(UInt32(entry.data.count)))
            central.append(le16(UInt16(nameData.count)))
            central.append(le16(0))         // extra
            central.append(le16(0))         // comment
            central.append(le16(0))         // disk
            central.append(le16(0))         // internal attrs
            central.append(le32(0))         // external attrs
            central.append(le32(UInt32(offsets[index])))
            central.append(nameData)
        }

        let centralOffset = out.count
        out.append(central)
        out.append(le32(0x06054b50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(UInt32(centralOffset)))
        out.append(le16(0))
        return out
    }

    private func le16(_ value: UInt16) -> Data {
        var value = value.littleEndian
        return Data(bytes: &value, count: 2)
    }

    private func le32(_ value: UInt32) -> Data {
        var value = value.littleEndian
        return Data(bytes: &value, count: 4)
    }

    private static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, components.year ?? 2026) - 1980
        let time = UInt16((components.hour ?? 0) << 11 | (components.minute ?? 0) << 5 | ((components.second ?? 0) / 2))
        let day = UInt16(year << 9 | (components.month ?? 0) << 5 | (components.day ?? 0))
        return (time, day)
    }
}

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

struct ZipReader {
    enum ZipError: LocalizedError {
        case notZip
        case truncated
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .notZip: return "不是有效的 ZIP / 备份文件"
            case .truncated: return "ZIP 文件不完整"
            case .unsupported(let method): return "不支持的 ZIP 压缩方式：\(method)"
            }
        }
    }

    private let data: Data
    private var entries: [String: (method: UInt16, compSize: Int, uncompSize: Int, localOffset: Int)] = [:]

    init(data: Data) throws {
        self.data = data
        try parseCentralDirectory()
    }

    var fileNames: [String] { Array(entries.keys) }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    /// 全部条目名（按出现顺序）
    var entryNames: [String] { Array(entries.keys).sorted() }

    func read(_ name: String) throws -> Data {
        guard let entry = entries[name] else { throw ZipError.notZip }
        let start = entry.localOffset
        guard start + 30 <= data.count else { throw ZipError.truncated }
        guard u32(start) == 0x04034b50 else { throw ZipError.notZip }
        let nameLength = Int(u16(start + 26))
        let extraLength = Int(u16(start + 28))
        let dataStart = start + 30 + nameLength + extraLength
        guard dataStart + entry.compSize <= data.count else { throw ZipError.truncated }
        let raw = data.subdata(in: dataStart..<(dataStart + entry.compSize))
        switch entry.method {
        case 0:
            return raw
        case 8:
            return try inflate(raw, expected: entry.uncompSize)
        default:
            throw ZipError.unsupported("method \(entry.method)")
        }
    }

    func text(_ name: String) throws -> String {
        let data = try read(name)
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: ZIP 结构

    private mutating func parseCentralDirectory() throws {
        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        var eocd = -1
        let lowerBound = max(0, data.count - 66_000)
        var index = data.count - 22
        while index >= lowerBound {
            if data[index] == signature[0],
               data[index + 1] == signature[1],
               data[index + 2] == signature[2],
               data[index + 3] == signature[3] {
                eocd = index
                break
            }
            index -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        let count = Int(u16(eocd + 10))
        var offset = Int(u32(eocd + 16))
        for _ in 0..<count {
            guard offset + 46 <= data.count, u32(offset) == 0x02014b50 else { throw ZipError.truncated }
            let method = u16(offset + 10)
            let compSize = Int(u32(offset + 20))
            let uncompSize = Int(u32(offset + 24))
            let nameLength = Int(u16(offset + 28))
            let extraLength = Int(u16(offset + 30))
            let commentLength = Int(u16(offset + 32))
            let localOffset = Int(u32(offset + 42))
            guard offset + 46 + nameLength <= data.count else { throw ZipError.truncated }
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            let name = String(decoding: nameData, as: UTF8.self)
            entries[name] = (method, compSize, uncompSize, localOffset)
            offset += 46 + nameLength + extraLength + commentLength
        }
    }

    private func u16(_ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func u32(_ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func inflate(_ input: Data, expected: Int) throws -> Data {
        guard expected > 0 else { return Data() }
        var output = Data(count: expected)
        let written: Int = output.withUnsafeMutableBytes { outputPointer in
            input.withUnsafeBytes { inputPointer in
                guard let outputBase = outputPointer.bindMemory(to: UInt8.self).baseAddress,
                      let inputBase = inputPointer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    outputBase, expected, inputBase, input.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw ZipError.truncated }
        return output.prefix(written)
    }
}
