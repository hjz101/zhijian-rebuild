// CodecSupport.swift —— 书源 JS 兼容层的原生算法底座（编码/摘要/对称加密/GZIP/RSA）
//
// 设计目标：
// - 纯系统框架（CommonCrypto / CryptoKit / Compression / Security），不引入 SPM 依赖；
// - 所有「重算法」都在 Swift 侧完成，JS 兼容层只做 API 形态转换；
// - 错误语义尽量接近 Java：参数非法时抛 `JSCodecError`，由 JSRuntime 映射成 JS 异常。
import Foundation
import CommonCrypto
import CryptoKit
import Compression
import Security

// MARK: - 错误

enum JSCodecError: LocalizedError {
    case unsupported(String)
    case invalidArgument(String)
    case cryptoFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let message): return "UnsupportedCodec: \(message)"
        case .invalidArgument(let message): return "InvalidArgument: \(message)"
        case .cryptoFailed(let message): return "CryptoFailed: \(message)"
        }
    }
}

// MARK: - 字符集 / Base64 / Hex

enum JSTextCodec {

    static func bytes(from string: String, charset: String?) -> [UInt8] {
        let name = normalizeCharset(charset)
        if name == "utf-8" { return Array(string.utf8) }
        if name == "iso-8859-1" || name == "latin1" { return string.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) } }
        if name == "utf-16le" || name == "utf-16" || name == "utf16" {
            var out: [UInt8] = []
            for unit in string.utf16 {
                out.append(UInt8(truncatingIfNeeded: unit))
                out.append(UInt8(truncatingIfNeeded: unit >> 8))
            }
            return out
        }
        if name == "utf-16be" {
            var out: [UInt8] = []
            for unit in string.utf16 {
                out.append(UInt8(truncatingIfNeeded: unit >> 8))
                out.append(UInt8(truncatingIfNeeded: unit))
            }
            return out
        }
        if name == "ascii" {
            return Array(string.utf8)
        }
        if let encoding = cfEncoding(named: name), let data = string.data(using: encoding) {
            return Array(data)
        }
        return Array(string.utf8)
    }

    static func string(from bytes: [UInt8], charset: String?) -> String {
        let name = normalizeCharset(charset)
        let data = Data(bytes)
        if name == "utf-8" { return String(data: data, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self) }
        if name == "iso-8859-1" || name == "latin1" {
            return String(bytes.map { Character(UnicodeScalar($0)) })
        }
        if name == "utf-16le" || name == "utf-16" || name == "utf16" {
            return String(data: data, encoding: .utf16LittleEndian) ?? String(decoding: bytes, as: UTF8.self)
        }
        if name == "utf-16be" {
            return String(data: data, encoding: .utf16BigEndian) ?? String(decoding: bytes, as: UTF8.self)
        }
        if name == "ascii" {
            return String(data: data, encoding: .ascii) ?? String(decoding: bytes, as: UTF8.self)
        }
        if let encoding = cfEncoding(named: name), let text = String(data: data, encoding: encoding) {
            return text
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func normalizedName(_ charset: String?) -> String {
        normalizeCharset(charset)
    }

    private static func normalizeCharset(_ charset: String?) -> String {
        guard let charset else { return "utf-8" }
        let lowered = charset.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")).lowercased()
        switch lowered {
        case "", "utf8", "utf-8", "unicode-1-1-utf-8": return "utf-8"
        case "gbk", "gb2312", "gb-2312", "gb18030", "gb-18030", "cp936", "x-gbk": return "gb18030"
        case "big5", "big-5", "cp950": return "big5"
        case "utf-16", "utf16", "utf-16le", "unicode": return "utf-16le"
        case "utf-16be": return "utf-16be"
        case "iso-8859-1", "iso8859-1", "latin1", "latin-1", "cp1252": return "iso-8859-1"
        case "us-ascii", "ascii": return "ascii"
        default: return lowered
        }
    }

    /// IANA charset 名 → NSStringEncoding（GB18030 / Big5 等走 CFString 转换）
    static func cfEncoding(named name: String) -> String.Encoding? {
        switch name {
        case "gb18030", "gbk", "gb2312":
            let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            return String.Encoding(rawValue: raw)
        case "big5":
            let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
            return String.Encoding(rawValue: raw)
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cf != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
    }

    static func base64Encode(_ bytes: [UInt8], urlSafe: Bool = false) -> String {
        var text = Data(bytes).base64EncodedString()
        if urlSafe {
            text = text.replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return text
    }

    static func base64Decode(_ text: String) -> [UInt8]? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        // Android Base64 / URL-safe 输入：统一换成标准字母表
        value = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder > 0 { value += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: value, options: [.ignoreUnknownCharacters]) else { return nil }
        return Array(data)
    }

    static func hexEncode(_ bytes: [UInt8]) -> String {
        var out = String()
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes { out += String(format: "%02x", byte) }
        return out
    }

    static func hexDecode(_ text: String) -> [UInt8]? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("0x") || value.hasPrefix("0X") { value.removeFirst(2) }
        guard value.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    static func looksLikeHex(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count % 2 == 0 else { return false }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 70) || (scalar.value >= 97 && scalar.value <= 102)
        }
    }
}

// MARK: - 摘要 / HMAC

enum JSDigest {

    private enum Algorithm {
        case md5, sha1, sha224, sha256, sha384, sha512
    }

    static func digest(algorithm: String, data: [UInt8]) -> [UInt8] {
        let alg = normalize(algorithm)
        let length = digestLength(alg)
        var output = [UInt8](repeating: 0, count: length)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress
            let count = data.count
            switch alg {
            case .md5: CC_MD5(base, CC_LONG(count), &output)
            case .sha1: CC_SHA1(base, CC_LONG(count), &output)
            case .sha224: CC_SHA224(base, CC_LONG(count), &output)
            case .sha256: CC_SHA256(base, CC_LONG(count), &output)
            case .sha384: CC_SHA384(base, CC_LONG(count), &output)
            case .sha512: CC_SHA512(base, CC_LONG(count), &output)
            }
        }
        return output
    }

    static func hmac(algorithm: String, key: [UInt8], data: [UInt8]) -> [UInt8] {
        let alg = normalize(algorithm)
        let ccAlg: CCHmacAlgorithm
        let length: Int
        switch alg {
        case .md5: ccAlg = CCHmacAlgorithm(kCCHmacAlgMD5); length = Int(CC_MD5_DIGEST_LENGTH)
        case .sha1: ccAlg = CCHmacAlgorithm(kCCHmacAlgSHA1); length = Int(CC_SHA1_DIGEST_LENGTH)
        case .sha224: ccAlg = CCHmacAlgorithm(kCCHmacAlgSHA224); length = Int(CC_SHA224_DIGEST_LENGTH)
        case .sha256: ccAlg = CCHmacAlgorithm(kCCHmacAlgSHA256); length = Int(CC_SHA256_DIGEST_LENGTH)
        case .sha384: ccAlg = CCHmacAlgorithm(kCCHmacAlgSHA384); length = Int(CC_SHA384_DIGEST_LENGTH)
        case .sha512: ccAlg = CCHmacAlgorithm(kCCHmacAlgSHA512); length = Int(CC_SHA512_DIGEST_LENGTH)
        }
        var output = [UInt8](repeating: 0, count: length)
        key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCHmac(ccAlg, keyPtr.baseAddress, key.count, dataPtr.baseAddress, data.count, &output)
            }
        }
        return output
    }

    private static func normalize(_ algorithm: String) -> Algorithm {
        let upper = algorithm.uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        if upper.contains("MD5") { return .md5 }
        if upper.contains("SHA224") { return .sha224 }
        if upper.contains("SHA1") || upper == "SHA" { return .sha1 }
        if upper.contains("SHA384") { return .sha384 }
        if upper.contains("SHA512") { return .sha512 }
        return .sha256
    }

    private static func digestLength(_ algorithm: Algorithm) -> Int {
        switch algorithm {
        case .md5: return Int(CC_MD5_DIGEST_LENGTH)
        case .sha1: return Int(CC_SHA1_DIGEST_LENGTH)
        case .sha224: return Int(CC_SHA224_DIGEST_LENGTH)
        case .sha256: return Int(CC_SHA256_DIGEST_LENGTH)
        case .sha384: return Int(CC_SHA384_DIGEST_LENGTH)
        case .sha512: return Int(CC_SHA512_DIGEST_LENGTH)
        }
    }
}

// MARK: - 对称加密（AES / DES / 3DES）

enum JSSymmetricCrypto {

    /// Java `Cipher` 的 CBC/ECB/CTR/CFB/OFB + PKCS5/PKCS7/NoPadding 子集。
    static func process(
        data: [UInt8],
        key: [UInt8],
        transformation: String,
        iv: [UInt8]?,
        decrypt: Bool
    ) throws -> [UInt8] {
        let parsed = try parse(transformation: transformation)
        let normalizedKey = normalizeKey(key, algorithm: parsed.algorithm)
        let blockSize = parsed.algorithm == .des || parsed.algorithm == .tripleDES ? kCCBlockSizeDES : kCCBlockSizeAES128
        let padding = parsed.mode == .ecb || parsed.mode == .cbc ? parsed.padding : false
        let ivBytes = normalizeIV(iv, blockSize: blockSize, mode: parsed.mode)

        var input = data
        if !decrypt, padding {
            let pad = blockSize - (input.count % blockSize)
            input.append(contentsOf: [UInt8](repeating: UInt8(pad), count: pad))
        }
        guard !decrypt || input.count % blockSize == 0 || parsed.mode == .ctr || parsed.mode == .cfb || parsed.mode == .ofb else {
            throw JSCodecError.invalidArgument("密文长度 \(input.count) 不是 \(blockSize) 的倍数")
        }

        let output: [UInt8]
        switch parsed.mode {
        case .ecb, .cbc:
            var options = CCOptions(0)
            if parsed.mode == .ecb { options |= CCOptions(kCCOptionECBMode) }
            if padding { options |= CCOptions(kCCOptionPKCS7Padding) }
            output = try cryptLegacy(
                input: input,
                key: normalizedKey,
                algorithm: parsed.ccAlgorithm,
                options: options,
                iv: parsed.mode == .cbc ? ivBytes : nil,
                decrypt: decrypt
            )
        case .ctr, .cfb, .ofb:
            output = try cryptStreamMode(
                input: input,
                key: normalizedKey,
                algorithm: parsed.ccAlgorithm,
                mode: parsed.ccMode,
                iv: ivBytes,
                decrypt: decrypt
            )
        }

        if decrypt, padding {
            return try unpad(output, blockSize: blockSize)
        }
        return output
    }

    struct Parsed {
        enum Algorithm { case aes, des, tripleDES }
        enum Mode { case ecb, cbc, ctr, cfb, ofb }
        var algorithm: Algorithm
        var mode: Mode
        var padding: Bool
        var ccAlgorithm: CCAlgorithm {
            switch algorithm {
            case .aes: return CCAlgorithm(kCCAlgorithmAES)
            case .des: return CCAlgorithm(kCCAlgorithmDES)
            case .tripleDES: return CCAlgorithm(kCCAlgorithm3DES)
            }
        }
        var ccMode: CCMode {
            switch mode {
            case .ecb: return CCMode(kCCModeECB)
            case .cbc: return CCMode(kCCModeCBC)
            case .ctr: return CCMode(kCCModeCTR)
            case .cfb: return CCMode(kCCModeCFB)
            case .ofb: return CCMode(kCCModeOFB)
            }
        }
    }

    static func parse(transformation raw: String) throws -> Parsed {
        let transformation = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = transformation.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        let algorithmName = (parts.first ?? "AES").uppercased()
        let modeName = parts.count > 1 ? parts[1].uppercased() : "ECB"
        let paddingName = parts.count > 2 ? parts[2].uppercased() : "PKCS5PADDING"

        let algorithm: Parsed.Algorithm
        switch algorithmName {
        case "AES": algorithm = .aes
        case "DES": algorithm = .des
        case "DESEDE", "3DES", "TRIPLEDES", "DES3": algorithm = .tripleDES
        default: throw JSCodecError.unsupported("对称加密算法 \(algorithmName)（支持 AES/DES/DESede）")
        }
        let mode: Parsed.Mode
        switch modeName {
        case "ECB": mode = .ecb
        case "CBC": mode = .cbc
        case "CTR": mode = .ctr
        case "CFB", "CFB8": mode = .cfb
        case "OFB": mode = .ofb
        default: throw JSCodecError.unsupported("加密模式 \(modeName)（支持 ECB/CBC/CTR/CFB/OFB）")
        }
        let padding: Bool
        switch paddingName {
        case "PKCS5PADDING", "PKCS7PADDING", "PKCS5", "PKCS7": padding = true
        case "NOPADDING", "NONE", "": padding = false
        default: throw JSCodecError.unsupported("填充方式 \(paddingName)（支持 PKCS5/PKCS7/NoPadding）")
        }
        return Parsed(algorithm: algorithm, mode: mode, padding: padding)
    }

    private static func normalizeKey(_ key: [UInt8], algorithm: Parsed.Algorithm) -> [UInt8] {
        switch algorithm {
        case .aes:
            if [16, 24, 32].contains(key.count) { return key }
            if key.count < 16 { return key + [UInt8](repeating: 0, count: 16 - key.count) }
            if key.count < 24 { return Array(key.prefix(16)) }
            if key.count < 32 { return Array(key.prefix(24)) }
            return Array(key.prefix(32))
        case .des:
            if key.count == 8 { return key }
            if key.count > 8 { return Array(key.prefix(8)) }
            return key + [UInt8](repeating: 0, count: 8 - key.count)
        case .tripleDES:
            if key.count == 24 { return key }
            if key.count > 24 { return Array(key.prefix(24)) }
            if key.count == 16 { return key + Array(key.prefix(8)) } // K1 K2 K1
            if key.count > 16 { return Array(key.prefix(24)) }
            return key + [UInt8](repeating: 0, count: 24 - key.count)
        }
    }

    private static func normalizeIV(_ iv: [UInt8]?, blockSize: Int, mode: Parsed.Mode) -> [UInt8] {
        if mode == .ecb { return [UInt8](repeating: 0, count: blockSize) }
        var value = iv ?? []
        if value.isEmpty { return [UInt8](repeating: 0, count: blockSize) }
        if value.count >= blockSize { return Array(value.prefix(blockSize)) }
        value.append(contentsOf: [UInt8](repeating: 0, count: blockSize - value.count))
        return value
    }

    private static func cryptLegacy(
        input: [UInt8],
        key: [UInt8],
        algorithm: CCAlgorithm,
        options: CCOptions,
        iv: [UInt8]?,
        decrypt: Bool
    ) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status: CCCryptorStatus = input.withUnsafeBytes { inputPtr in
            key.withUnsafeBytes { keyPtr in
                if let iv, !iv.isEmpty {
                    return iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(decrypt ? kCCDecrypt : kCCEncrypt),
                            algorithm, options,
                            keyPtr.baseAddress, key.count, ivPtr.baseAddress,
                            inputPtr.baseAddress, input.count,
                            &output, output.count, &moved
                        )
                    }
                }
                return CCCrypt(
                    CCOperation(decrypt ? kCCDecrypt : kCCEncrypt),
                    algorithm, options,
                    keyPtr.baseAddress, key.count, nil,
                    inputPtr.baseAddress, input.count,
                    &output, output.count, &moved
                )
            }
        }
        guard status == kCCSuccess else {
            throw JSCodecError.cryptoFailed("CCCrypt 失败（status=\(status)，可能是密钥/IV 长度或密文格式不正确）")
        }
        return Array(output.prefix(moved))
    }

    private static func cryptStreamMode(
        input: [UInt8],
        key: [UInt8],
        algorithm: CCAlgorithm,
        mode: CCMode,
        iv: [UInt8],
        decrypt: Bool
    ) throws -> [UInt8] {
        var cryptor: CCCryptorRef?
        let createStatus: CCCryptorStatus = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                CCCryptorCreateWithMode(
                    CCOperation(decrypt ? kCCDecrypt : kCCEncrypt),
                    mode,
                    algorithm,
                    CCPadding(ccNoPadding),
                    ivPtr.baseAddress,
                    keyPtr.baseAddress,
                    key.count,
                    nil, 0, 0,
                    CCModeOptions(0),
                    &cryptor
                )
            }
        }
        guard createStatus == kCCSuccess, let cryptor else {
            throw JSCodecError.cryptoFailed("CCCryptorCreateWithMode 失败（status=\(createStatus)）")
        }
        defer { CCCryptorRelease(cryptor) }

        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let updateStatus: CCCryptorStatus = input.withUnsafeBytes { inputPtr in
            CCCryptorUpdate(cryptor, inputPtr.baseAddress, input.count, &output, output.count, &moved)
        }
        guard updateStatus == kCCSuccess else {
            throw JSCodecError.cryptoFailed("CCCryptorUpdate 失败（status=\(updateStatus)）")
        }
        var finalMoved = 0
        let remaining = output.count - moved
        let finalStatus: CCCryptorStatus = output.withUnsafeMutableBytes { pointer in
            let base = pointer.baseAddress!.advanced(by: moved)
            return CCCryptorFinal(cryptor, base, remaining, &finalMoved)
        }
        guard finalStatus == kCCSuccess else {
            throw JSCodecError.cryptoFailed("CCCryptorFinal 失败（status=\(finalStatus)）")
        }
        return Array(output.prefix(moved + finalMoved))
    }

    private static func unpad(_ input: [UInt8], blockSize: Int) throws -> [UInt8] {
        guard let last = input.last else { return input }
        let pad = Int(last)
        guard pad > 0, pad <= blockSize, pad <= input.count else {
            throw JSCodecError.cryptoFailed("PKCS5/7 填充非法（末字节 \(last)）")
        }
        guard input.suffix(pad).allSatisfy({ $0 == last }) else {
            throw JSCodecError.cryptoFailed("PKCS5/7 填充字节不一致")
        }
        return Array(input.dropLast(pad))
    }
}

// MARK: - GZIP

enum JSGzip {

    static func gzip(_ input: [UInt8]) throws -> [UInt8] {
        let deflated = try inflateOrDeflate(input, encode: true)
        var output: [UInt8] = [0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff]
        output.append(contentsOf: deflated)
        var crc = crc32(input).littleEndian
        withUnsafeBytes(of: &crc) { output.append(contentsOf: $0) }
        var size = UInt32(truncatingIfNeeded: input.count).littleEndian
        withUnsafeBytes(of: &size) { output.append(contentsOf: $0) }
        return output
    }

    static func gunzip(_ input: [UInt8]) throws -> [UInt8] {
        let bytes = input
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b else {
            throw JSCodecError.invalidArgument("不是合法的 gzip 数据")
        }
        guard bytes[2] == 8 else {
            throw JSCodecError.unsupported("gzip 压缩方法 \(bytes[2])")
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw JSCodecError.invalidArgument("gzip FEXTRA 截断") }
            let length = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + length
        }
        if flags & 0x08 != 0 { // FNAME
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset <= bytes.count - 8 else {
            throw JSCodecError.invalidArgument("gzip 数据截断")
        }
        let payload = Array(bytes[offset..<(bytes.count - 8)])
        return try inflateOrDeflate(payload, encode: false)
    }

    private static func inflateOrDeflate(_ input: [UInt8], encode: Bool) throws -> [UInt8] {
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        )
        let initStatus = compression_stream_init(&stream, encode ? COMPRESSION_STREAM_ENCODE : COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else {
            throw JSCodecError.cryptoFailed("compression_stream_init 失败（status=\(initStatus.rawValue)）")
        }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var output: [UInt8] = []
        output.reserveCapacity(max(input.count * 2, 1024))

        return try input.withUnsafeBufferPointer { source -> [UInt8] in
            // 空输入时给一个合法非空指针，避免 withUnsafeBufferPointer 的 baseAddress 为 nil
            let dummy: [UInt8] = [0]
            return try dummy.withUnsafeBufferPointer { dummyBuffer in
                stream.src_ptr = source.baseAddress ?? dummyBuffer.baseAddress!
                stream.src_size = input.count
                var status = COMPRESSION_STATUS_OK
                repeat {
                    stream.dst_ptr = buffer
                    stream.dst_size = bufferSize
                    status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    switch status {
                    case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                        let produced = bufferSize - stream.dst_size
                        if produced > 0 { output.append(contentsOf: UnsafeBufferPointer(start: buffer, count: produced)) }
                    default:
                        throw JSCodecError.cryptoFailed("gzip \(encode ? "压缩" : "解压")失败（status=\(status.rawValue)）")
                    }
                } while status == COMPRESSION_STATUS_OK
                return output
            }
        }
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - RSA（PKCS#1 / PKCS#8 / X.509 最小 DER 解析）

enum JSRSA {

    static func sign(algorithm: String, keyDER: [UInt8], data: [UInt8]) throws -> [UInt8] {
        let secKey = try makeKey(der: keyDER, privateKey: true)
        let secAlgorithm = try signatureAlgorithm(algorithm)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(secKey, secAlgorithm, Data(data) as CFData, &error) else {
            throw JSCodecError.cryptoFailed("RSA 签名失败：\(error?.takeRetainedValue().localizedDescription ?? "未知错误")")
        }
        return Array(signature as Data)
    }

    static func verify(algorithm: String, keyDER: [UInt8], data: [UInt8], signature: [UInt8]) throws -> Bool {
        let secKey = try makeKey(der: keyDER, privateKey: false)
        let secAlgorithm = try signatureAlgorithm(algorithm)
        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(secKey, secAlgorithm, Data(data) as CFData, Data(signature) as CFData, &error)
        if !ok, let error {
            _ = error.takeRetainedValue()
        }
        return ok
    }

    static func makeKey(der: [UInt8], privateKey: Bool) throws -> SecKey {
        guard let pkcs1 = normalizeKeyDER(der, privateKey: privateKey) else {
            throw JSCodecError.invalidArgument("无法解析 RSA 密钥 DER（支持 PKCS#1 / PKCS#8 / X.509 SubjectPublicKeyInfo）")
        }
        let bits = modulusBits(pkcs1) ?? 2048
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: privateKey ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: bits
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(Data(pkcs1) as CFData, attributes as CFDictionary, &error) else {
            throw JSCodecError.cryptoFailed("SecKeyCreateWithData 失败：\(error?.takeRetainedValue().localizedDescription ?? "未知错误")")
        }
        return key
    }

    private static func signatureAlgorithm(_ algorithm: String) throws -> SecKeyAlgorithm {
        let upper = algorithm.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        let pss = upper.contains("PSS")
        if upper.contains("MD5") {
            throw JSCodecError.unsupported("RSA/MD5 签名（Security 框架不支持 MD5withRSA）")
        }
        if upper.contains("SHA256") {
            return pss ? .rsaSignatureMessagePSSSHA256 : .rsaSignatureMessagePKCS1v15SHA256
        }
        if upper.contains("SHA384") {
            return pss ? .rsaSignatureMessagePSSSHA384 : .rsaSignatureMessagePKCS1v15SHA384
        }
        if upper.contains("SHA512") {
            return pss ? .rsaSignatureMessagePSSSHA512 : .rsaSignatureMessagePKCS1v15SHA512
        }
        if upper.contains("SHA1") || upper.contains("SHA") {
            return pss ? .rsaSignatureMessagePSSSHA1 : .rsaSignatureMessagePKCS1v15SHA1
        }
        throw JSCodecError.unsupported("签名算法 \(algorithm)（支持 SHA1/SHA256/SHA384/SHA512withRSA，可带 PSS）")
    }

    // MARK: DER

    private struct DERNode {
        var tag: UInt8
        var content: [UInt8]
        var raw: [UInt8]
    }

    private static func readNode(_ bytes: [UInt8], _ offset: Int) -> (node: DERNode, next: Int)? {
        guard offset + 2 <= bytes.count else { return nil }
        let tag = bytes[offset]
        var cursor = offset + 1
        var length = Int(bytes[cursor])
        cursor += 1
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, cursor + count <= bytes.count else { return nil }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[cursor])
                cursor += 1
            }
        }
        guard cursor + length <= bytes.count else { return nil }
        let content = Array(bytes[cursor..<(cursor + length)])
        let raw = Array(bytes[offset..<(cursor + length)])
        return (DERNode(tag: tag, content: content, raw: raw), cursor + length)
    }

    private static func children(_ bytes: [UInt8]) -> [DERNode] {
        var out: [DERNode] = []
        var cursor = 0
        while cursor < bytes.count {
            guard let (node, next) = readNode(bytes, cursor) else { break }
            out.append(node)
            cursor = next
        }
        return out
    }

    /// 统一成 PKCS#1：私钥 SEQUENCE{version,n,e,d,...}；公钥 SEQUENCE{n,e}
    private static func normalizeKeyDER(_ der: [UInt8], privateKey: Bool) -> [UInt8]? {
        guard let (top, _) = readNode(der, 0), top.tag == 0x30 else { return nil }
        let items = children(top.content)
        guard !items.isEmpty else { return nil }

        // PKCS#8 PrivateKeyInfo: version, AlgorithmIdentifier, OCTET STRING
        if privateKey, items.count >= 3, items[0].tag == 0x02, items[1].tag == 0x30, items[2].tag == 0x04 {
            return items[2].content
        }
        // X.509 SubjectPublicKeyInfo: AlgorithmIdentifier, BIT STRING
        if !privateKey, items.count >= 2, items[0].tag == 0x30, items[1].tag == 0x03, !items[1].content.isEmpty {
            return Array(items[1].content.dropFirst()) // 去掉 unused-bits 字节
        }
        // 已经是 PKCS#1
        if privateKey, items.count >= 9, items[0].tag == 0x02, items[1].tag == 0x02 {
            return der
        }
        if !privateKey, items.count == 2, items[0].tag == 0x02, items[1].tag == 0x02 {
            return der
        }
        // 宽松回退：私钥直接返回原文，公钥取第一个 INTEGER 开始的 SEQUENCE
        return privateKey ? der : nil
    }

    private static func modulusBits(_ pkcs1: [UInt8]) -> Int? {
        guard let (top, _) = readNode(pkcs1, 0) else { return nil }
        let items = children(top.content)
        guard let modulus = items.first(where: { $0.tag == 0x02 }) else { return nil }
        var bytes = modulus.content
        while bytes.first == 0 { bytes.removeFirst() }
        guard let first = bytes.first else { return nil }
        var bits = bytes.count * 8
        var value = first
        while value & 0x80 == 0 { bits -= 1; value <<= 1 }
        // Security 只接受常见位数，向上取整避免 SecKeyCreateWithData 拒绝
        let common = [512, 768, 1024, 1536, 2048, 3072, 4096, 6144, 8192]
        return common.first(where: { $0 >= bits }) ?? bits
    }
}
