// JSRuntime+Native.swift —— packages_stub.js / jsoup_bridge.js 依赖的原生全局函数
//
// 这些函数是兼容层唯一的重算法入口（与 QiReader 的 9 个 `_native*` 对应，另有
// digest/HMAC/UUID 等少量补充）。统一约定：
// - 字节数组：JS 普通数组（元素 0…255）；
// - 加密输入输出：base64 字符串（避免跨桥大数组往返）；
// - 失败：设置 JSContext.exception，JS 侧捕获为异常。
import Foundation
import JavaScriptCore

// JavaScriptCore 只识别 `@convention(block)` 标注的 Swift 闭包
typealias NativeBlock0 = @convention(block) () -> JSValue
typealias NativeBlock1 = @convention(block) (JSValue) -> JSValue
typealias NativeBlock2 = @convention(block) (JSValue, JSValue) -> JSValue
typealias NativeBlock3 = @convention(block) (JSValue, JSValue, JSValue) -> JSValue
typealias NativeBlock4 = @convention(block) (JSValue, JSValue, JSValue, JSValue) -> JSValue
typealias NativeBlock5 = @convention(block) (JSValue, JSValue, JSValue, JSValue, JSValue) -> JSValue
typealias NativeVoid0 = @convention(block) () -> Void
typealias NativeVoid2 = @convention(block) (JSValue, JSValue) -> Void
typealias NativeVoid3 = @convention(block) (JSValue, JSValue, JSValue) -> Void
typealias NativeVoid4 = @convention(block) (JSValue, JSValue, JSValue, JSValue) -> Void

extension JSRuntime {

    // MARK: 安装

    func installNativeGlobals(_ ctx: JSContext) {
        let strToBytes: NativeBlock2 = { [weak self] stringValue, charsetValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let bytes = JSTextCodec.bytes(from: Self.stringArg(stringValue), charset: Self.stringArg(charsetValue))
            return self.bytesValue(bytes)
        }
        ctx.setObject(strToBytes, forKeyedSubscript: "_nativeStrToBytes" as NSString)

        let bytesToStr: NativeBlock2 = { [weak self] bytesValue, charsetValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let bytes = Self.bytesArg(bytesValue)
            return JSValue(object: JSTextCodec.string(from: bytes, charset: Self.stringArg(charsetValue)), in: self.context)
        }
        ctx.setObject(bytesToStr, forKeyedSubscript: "_nativeBytesToStr" as NSString)

        let base64Encode: NativeBlock1 = { [weak self] bytesValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: JSTextCodec.base64Encode(Self.bytesArg(bytesValue)), in: self.context)
        }
        ctx.setObject(base64Encode, forKeyedSubscript: "_nativeBase64Encode" as NSString)

        let base64Decode: NativeBlock1 = { [weak self] stringValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let text = Self.stringArg(stringValue)
            guard let bytes = JSTextCodec.base64Decode(text) else {
                return self.nativeFailure("base64 解码失败：\(String(text.prefix(80)))")
            }
            return self.bytesValue(bytes)
        }
        ctx.setObject(base64Decode, forKeyedSubscript: "_nativeBase64DecodeToBytes" as NSString)

        let cipher: NativeBlock5 = { [weak self] dataValue, keyValue, transformationValue, ivValue, decryptValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let data = Self.base64OrBytesArg(dataValue)
            let key = Self.base64OrBytesArg(keyValue)
            let ivRaw = ivValue.isUndefined || ivValue.isNull ? [UInt8]() : Self.base64OrBytesArg(ivValue)
            let transformation = Self.stringArg(transformationValue)
            let decrypt = decryptValue.toBool()
            do {
                let result = try JSSymmetricCrypto.process(
                    data: data,
                    key: key,
                    transformation: transformation,
                    iv: ivRaw.isEmpty ? nil : ivRaw,
                    decrypt: decrypt
                )
                return JSValue(object: JSTextCodec.base64Encode(result), in: self.context)
            } catch {
                return self.nativeFailure(error.localizedDescription)
            }
        }
        ctx.setObject(cipher, forKeyedSubscript: "_nativeCipherProcess" as NSString)

        let gzip: NativeBlock1 = { [weak self] bytesValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            do {
                return self.bytesValue(try JSGzip.gzip(Self.bytesArg(bytesValue)))
            } catch {
                return self.nativeFailure(error.localizedDescription)
            }
        }
        ctx.setObject(gzip, forKeyedSubscript: "_nativeGzip" as NSString)

        let gunzip: NativeBlock1 = { [weak self] bytesValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            do {
                return self.bytesValue(try JSGzip.gunzip(Self.bytesArg(bytesValue)))
            } catch {
                return self.nativeFailure(error.localizedDescription)
            }
        }
        ctx.setObject(gunzip, forKeyedSubscript: "_nativeGunzip" as NSString)

        let jsonPath: NativeBlock3 = { [weak self] jsonValue, pathValue, suppressValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let suppress = suppressValue.toBool()
            guard let root = Self.jsonRoot(from: jsonValue) else {
                if suppress { return JSValue(nullIn: self.context) }
                return self.nativeFailure("JsonPath.read: 输入不是合法 JSON")
            }
            let path = Self.stringArg(pathValue)
            guard !path.isEmpty else { return self.toJS(root) }
            let values = JSONPath.evaluate(root, path)
            guard !values.isEmpty else { return JSValue(nullIn: self.context) }
            if values.count == 1 { return self.toJS(values[0]) }
            return self.toJS(values.map { JSONValueUtil.normalize($0) })
        }
        ctx.setObject(jsonPath, forKeyedSubscript: "_nativeJsonPathRead" as NSString)

        let sleep: @convention(block) (JSValue) -> Void = { millisecondsValue in
            let requested = millisecondsValue.toDouble()
            let capped = max(0, min(2000, requested))
            if capped > 0 { Thread.sleep(forTimeInterval: capped / 1000) }
        }
        ctx.setObject(sleep, forKeyedSubscript: "_nativeSleepMillis" as NSString)

        let digest: NativeBlock2 = { [weak self] bytesValue, algorithmValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let bytes = Self.bytesArg(bytesValue)
            let value = JSDigest.digest(algorithm: Self.stringArg(algorithmValue), data: bytes)
            return JSValue(object: JSTextCodec.base64Encode(value), in: self.context)
        }
        ctx.setObject(digest, forKeyedSubscript: "_nativeDigestBase64" as NSString)

        let hmac: NativeBlock3 = { [weak self] keyValue, dataValue, algorithmValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let value = JSDigest.hmac(
                algorithm: Self.stringArg(algorithmValue),
                key: Self.bytesArg(keyValue),
                data: Self.bytesArg(dataValue)
            )
            return JSValue(object: JSTextCodec.base64Encode(value), in: self.context)
        }
        ctx.setObject(hmac, forKeyedSubscript: "_nativeHMacBase64" as NSString)

        let randomUUID: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: UUID().uuidString.lowercased(), in: self.context)
        }
        ctx.setObject(randomUUID, forKeyedSubscript: "_nativeRandomUUID" as NSString)
        // MARK: ZIP（EPUB / 压缩包书源）
        let zipRead: NativeBlock3 = { [weak self] sourceValue, entryValue, isBase64Value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let source = Self.stringArg(sourceValue)
            let entry = Self.stringArg(entryValue)
            let isBase64 = isBase64Value.toBool()
            guard let data = self.loadZipSource(source, isBase64: isBase64) else {
                return self.nativeFailure("ZIP 读取失败：无法加载 \(String(source.prefix(120)))")
            }
            guard let payload = self.archiveRead(source: source, entry: entry, isBase64: isBase64) else {
                return self.nativeFailure("ZIP/RAR/7z 读取失败：\(entry)")
            }
            return JSValue(object: String(decoding: payload, as: UTF8.self), in: self.context)
        }
        ctx.setObject(zipRead, forKeyedSubscript: "_nativeZipRead" as NSString)

        let zipBytes: NativeBlock3 = { [weak self] sourceValue, entryValue, isBase64Value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let source = Self.stringArg(sourceValue)
            let entry = Self.stringArg(entryValue)
            let isBase64 = isBase64Value.toBool()
            guard let data = self.loadZipSource(source, isBase64: isBase64) else {
                return self.nativeFailure("ZIP 读取失败：无法加载压缩包")
            }
            guard let payload = self.archiveRead(source: source, entry: entry, isBase64: isBase64) else {
                return self.nativeFailure("ZIP/RAR/7z 读取失败：\(entry)")
            }
            return self.bytesValue(Array(payload))
        }
        ctx.setObject(zipBytes, forKeyedSubscript: "_nativeZipBytes" as NSString)

        let zipList: NativeBlock2 = { [weak self] sourceValue, isBase64Value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let source = Self.stringArg(sourceValue)
            guard let names = self.archiveList(source: source, isBase64: isBase64Value.toBool()) else {
                return self.nativeFailure("ZIP/RAR/7z 列表读取失败")
            }
            return JSValue(object: names, in: self.context)
        }
        ctx.setObject(zipList, forKeyedSubscript: "_nativeZipList" as NSString)


        // 文档/诊断：让 JS 能判断 native 兼容层是否已安装
        ctx.setObject(JSValue(bool: true, in: ctx), forKeyedSubscript: "_zhijianNativeBridgeLoaded" as NSString)
    }

    // MARK: 错误与参数

    /// 读取压缩包条目：ZIP 优先，失败后回退 libarchive（RAR/7z）
    func archiveRead(source: String, entry: String, isBase64: Bool) -> Data? {
        guard let data = loadZipSource(source, isBase64: isBase64) else { return nil }
        if let zip = try? ZipReader(data: data), let payload = try? zip.read(entry) {
            return payload
        }
        return try? ArchiveReader.read(data: data, entry: entry)
    }

    func archiveList(source: String, isBase64: Bool) -> [String]? {
        guard let data = loadZipSource(source, isBase64: isBase64) else { return nil }
        if let zip = try? ZipReader(data: data) { return zip.fileNames }
        return try? ArchiveReader.list(data: data).map(\.name)
    }

    @discardableResult
    func archiveExtractAll(source: String, isBase64: Bool, to directory: URL) -> Bool {
        guard let data = loadZipSource(source, isBase64: isBase64) else { return false }
        if let zip = try? ZipReader(data: data) {
            var extracted = false
            for name in zip.fileNames {
                let normalized = name.replacingOccurrences(of: "\\", with: "/")
                guard !normalized.hasPrefix("/"), !normalized.split(separator: "/").contains(".."), !normalized.hasSuffix("/"),
                      let payload = try? zip.read(name) else { continue }
                let target = directory.appendingPathComponent(normalized).standardizedFileURL
                guard target.path.hasPrefix(directory.standardizedFileURL.path + "/") else { continue }
                try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? payload.write(to: target, options: .atomic)
                extracted = true
            }
            return extracted
        }
        do {
            try ArchiveReader.extractAll(data: data, to: directory)
            return true
        } catch {
            return false
        }
    }

    /// 加载 ZIP 数据来源：base64 / HTTP(S) / 绝对路径 / 缓存目录相对路径
    func loadZipSource(_ source: String, isBase64: Bool) -> Data? {
        let raw = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if isBase64 {
            let cleaned = raw.replacingOccurrences(of: "data:application/zip;base64,", with: "")
            return Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters)
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://"),
           let url = URL(string: raw),
           let data = try? Data(contentsOf: url) {
            return data
        }
        if raw.hasPrefix("/") {
            return try? Data(contentsOf: URL(fileURLWithPath: raw))
        }
        if let url = resolveCacheURL(raw), let data = try? Data(contentsOf: url) {
            return data
        }
        if let url = URL(string: raw), url.isFileURL {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    func nativeFailure(_ message: String) -> JSValue {
        context.exception = JSValue(newErrorFromMessage: message, in: context)
        return JSValue(undefinedIn: context)
    }

    static func intArg(_ value: JSValue?) -> Int {
        guard let value, !value.isUndefined, !value.isNull else { return 0 }
        return Int(value.toInt32())
    }

    static func bytesArg(_ value: JSValue?) -> [UInt8] {
        guard let value, !value.isUndefined, !value.isNull else { return [] }
        if value.isString { return Array((value.toString() ?? "").utf8) }
        if value.isArray, let items = value.toArray() {
            return items.map { UInt8(truncatingIfNeeded: ($0 as? NSNumber)?.intValue ?? 0) }
        }
        if value.isObject {
            let length = Int(value.objectForKeyedSubscript("length")?.toInt32() ?? 0)
            if length > 0 {
                var out = [UInt8]()
                out.reserveCapacity(length)
                for index in 0..<length {
                    out.append(UInt8(truncatingIfNeeded: Int(value.objectAtIndexedSubscript(index).toInt32())))
                }
                return out
            }
        }
        return Array((value.toString() ?? "").utf8)
    }

    /// base64 字符串或字节数组（Cipher 的 key/iv/data 通道用）
    static func base64OrBytesArg(_ value: JSValue?) -> [UInt8] {
        guard let value, !value.isUndefined, !value.isNull else { return [] }
        if value.isString {
            let text = value.toString() ?? ""
            if let bytes = JSTextCodec.base64Decode(text) { return bytes }
            return Array(text.utf8)
        }
        return bytesArg(value)
    }

    static func jsonRoot(from value: JSValue?) -> Any? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        if value.isString { return JSONValueUtil.parseJSON(value.toString() ?? "") }
        if value.isObject {
            if let dictionary = value.toDictionary() { return JSONValueUtil.normalize(dictionary) }
            if let array = value.toArray() { return JSONValueUtil.normalize(array) }
        }
        return nil
    }

    func bytesValue(_ bytes: [UInt8]) -> JSValue {
        let array = JSValue(newArrayIn: context)!
        for (index, byte) in bytes.enumerated() {
            array.setObject(JSValue(int32: Int32(byte), in: context), atIndexedSubscript: index)
        }
        return array
    }
}
