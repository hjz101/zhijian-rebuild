// JSRuntime+JavaCompat.swift —— Legado `java.*` 兼容 API 的扩充（编码/加密/文件/网络/签名）
//
// 已有基础方法（ajax/get/post/head/getString/getElements/base64Encode…）在
// JSRuntime.buildJava() 里；本文件补充 QiReader 级别书源常用的其余 java.*，
// 并对 WebView 系列给出明确的 unsupported 诊断（而不是 `undefined is not a function`）。
import Foundation
import JavaScriptCore
import UIKit

extension JSRuntime {

    // MARK: 安装入口（由 buildJava 调用）

    func installJavaCompatMethods(on java: JSValue) {
        let ctx = context

        // MARK: 编码 / 摘要

        let base64DecodeToByteArray: NativeBlock1 = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let text = Self.stringArg(value)
            guard let bytes = JSTextCodec.base64Decode(text) else {
                return self.nativeFailure("base64DecodeToByteArray: 非法 base64")
            }
            return self.bytesValue(bytes)
        }
        java.setObject(base64DecodeToByteArray, forKeyedSubscript: "base64DecodeToByteArray" as NSString)

        let hexDecodeToByteArray: NativeBlock1 = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let bytes = JSTextCodec.hexDecode(Self.stringArg(value)) else {
                return self.nativeFailure("hexDecodeToByteArray: 非法 hex")
            }
            return self.bytesValue(bytes)
        }
        java.setObject(hexDecodeToByteArray, forKeyedSubscript: "hexDecodeToByteArray" as NSString)

        let digestHex: NativeBlock2 = { [weak self] dataValue, algorithmValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let bytes = JSTextCodec.bytes(from: Self.stringArg(dataValue), charset: "utf-8")
            let digest = JSDigest.digest(algorithm: Self.stringArg(algorithmValue), data: bytes)
            return JSValue(object: JSTextCodec.hexEncode(digest), in: self.context)
        }
        java.setObject(digestHex, forKeyedSubscript: "digestHex" as NSString)

        let digestBase64Str: NativeBlock2 = { [weak self] dataValue, algorithmValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let bytes = JSTextCodec.bytes(from: Self.stringArg(dataValue), charset: "utf-8")
            let digest = JSDigest.digest(algorithm: Self.stringArg(algorithmValue), data: bytes)
            return JSValue(object: JSTextCodec.base64Encode(digest), in: self.context)
        }
        java.setObject(digestBase64Str, forKeyedSubscript: "digestBase64Str" as NSString)

        let md5Encode16: NativeBlock1 = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let digest = JSDigest.digest(algorithm: "MD5", data: JSTextCodec.bytes(from: Self.stringArg(value), charset: "utf-8"))
            let hex = JSTextCodec.hexEncode(digest)
            let start = hex.index(hex.startIndex, offsetBy: min(8, hex.count))
            let end = hex.index(hex.startIndex, offsetBy: min(24, hex.count))
            return JSValue(object: String(hex[start..<end]), in: self.context)
        }
        java.setObject(md5Encode16, forKeyedSubscript: "md5Encode16" as NSString)

        let hmacHex: NativeBlock3 = { [weak self] dataValue, algorithmValue, keyValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let data = JSTextCodec.bytes(from: Self.stringArg(dataValue), charset: "utf-8")
            let key = JSTextCodec.bytes(from: Self.stringArg(keyValue), charset: "utf-8")
            let mac = JSDigest.hmac(algorithm: Self.stringArg(algorithmValue), key: key, data: data)
            return JSValue(object: JSTextCodec.hexEncode(mac), in: self.context)
        }
        java.setObject(hmacHex, forKeyedSubscript: "HMacHex" as NSString)

        let hmacBase64: NativeBlock3 = { [weak self] dataValue, algorithmValue, keyValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let data = JSTextCodec.bytes(from: Self.stringArg(dataValue), charset: "utf-8")
            let key = JSTextCodec.bytes(from: Self.stringArg(keyValue), charset: "utf-8")
            let mac = JSDigest.hmac(algorithm: Self.stringArg(algorithmValue), key: key, data: data)
            return JSValue(object: JSTextCodec.base64Encode(mac), in: self.context)
        }
        java.setObject(hmacBase64, forKeyedSubscript: "HMacBase64" as NSString)

        // MARK: 字符串 / URI

        let strToBytes: NativeBlock2 = { [weak self] value, charset in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return self.bytesValue(JSTextCodec.bytes(from: Self.stringArg(value), charset: Self.stringArg(charset)))
        }
        java.setObject(strToBytes, forKeyedSubscript: "strToBytes" as NSString)

        let bytesToStr: NativeBlock2 = { [weak self] value, charset in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: JSTextCodec.string(from: Self.bytesArg(value), charset: Self.stringArg(charset)), in: self.context)
        }
        java.setObject(bytesToStr, forKeyedSubscript: "bytesToStr" as NSString)

        let encodeURI: NativeBlock2 = { [weak self] value, encoding in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let charset = Self.stringArg(encoding).isEmpty ? "utf-8" : Self.stringArg(encoding)
            return JSValue(object: Self.percentEncode(Self.stringArg(value), charset: charset), in: self.context)
        }
        java.setObject(encodeURI, forKeyedSubscript: "encodeURI" as NSString)
        java.setObject(encodeURI, forKeyedSubscript: "encodeURIWithCharset" as NSString)

        let decodeURI: NativeBlock2 = { [weak self] value, encoding in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let charset = Self.stringArg(encoding).isEmpty ? "utf-8" : Self.stringArg(encoding)
            return JSValue(object: Self.percentDecode(Self.stringArg(value), charset: charset), in: self.context)
        }
        java.setObject(decodeURI, forKeyedSubscript: "decodeURI" as NSString)
        java.setObject(decodeURI, forKeyedSubscript: "decodeURIWithCharset" as NSString)

        let toURL: NativeBlock2 = { [weak self] urlValue, baseValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return self.makeURLObject(raw: Self.stringArg(urlValue), base: Self.stringArg(baseValue))
        }
        java.setObject(toURL, forKeyedSubscript: "toURL" as NSString)

        let htmlFormat: NativeBlock1 = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: HtmlFormatter.formatIfNeeded(Self.stringArg(value)), in: self.context)
        }
        java.setObject(htmlFormat, forKeyedSubscript: "htmlFormat" as NSString)

        let strToInt: NativeBlock1 = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let text = Self.stringArg(value).trimmingCharacters(in: .whitespacesAndNewlines)
            return JSValue(int32: Int32(Int(text) ?? 0), in: self.context)
        }
        java.setObject(strToInt, forKeyedSubscript: "strToInt" as NSString)

        let substring: NativeBlock3 = { [weak self] value, startValue, endValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let text = Self.stringArg(value)
            let start = max(0, Self.intArg(startValue))
            let end = endValue.isUndefined || endValue.isNull ? text.count : min(text.count, Self.intArg(endValue))
            guard start <= end else { return JSValue(object: "", in: self.context) }
            return JSValue(object: String(text.dropFirst(start).prefix(end - start)), in: self.context)
        }
        java.setObject(substring, forKeyedSubscript: "substring" as NSString)

        let identity: NativeBlock1 = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: Self.stringArg(value), in: self.context)
        }
        java.setObject(identity, forKeyedSubscript: "t2s" as NSString)
        java.setObject(identity, forKeyedSubscript: "s2t" as NSString)

        let randomUUID: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: UUID().uuidString.lowercased(), in: self.context)
        }
        java.setObject(randomUUID, forKeyedSubscript: "randomUUID" as NSString)

        let androidId: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: DeviceIdentity.androidId, in: self.context)
        }
        java.setObject(androidId, forKeyedSubscript: "androidId" as NSString)

        // 聚合源常把 deviceID 作为设备指纹上送；返回同样的 16 位 hex，
        // 避免被后端判为「伪造设备码」而 429。
        let deviceId: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: DeviceIdentity.deviceId, in: self.context)
        }
        java.setObject(deviceId, forKeyedSubscript: "deviceID" as NSString)

        let currentTime: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            return JSValue(object: formatter.string(from: Date()), in: self.context)
        }
        java.setObject(currentTime, forKeyedSubscript: "currentTime" as NSString)

        let timeFormatUTC: NativeBlock3 = { [weak self] timeValue, patternValue, offsetValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let interval = timeValue.isUndefined || timeValue.isNull ? Date().timeIntervalSince1970 : timeValue.toDouble() / 1000
            let pattern = Self.stringArg(patternValue).isEmpty ? "yyyy/MM/dd HH:mm" : Self.stringArg(patternValue)
            let offset = Int(offsetValue.toDouble())
            return JSValue(object: Self.formatDate(Date(timeIntervalSince1970: interval), pattern: pattern, timeZoneOffsetHours: offset), in: self.context)
        }
        java.setObject(timeFormatUTC, forKeyedSubscript: "timeFormatUTC" as NSString)

        // MARK: 对称加密

        let createSymmetricCrypto: NativeBlock3 = { [weak self] transformationValue, keyValue, ivValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let transformation = Self.stringArg(transformationValue)
            var keyBytes = Self.keyBytesArg(keyValue)
            if keyBytes.isEmpty {
                let algorithm = transformation.uppercased()
                let size = algorithm.hasPrefix("DESEDE") || algorithm.hasPrefix("3DES") ? 24 : (algorithm.hasPrefix("DES") ? 8 : 16)
                keyBytes = (0..<size).map { _ in UInt8.random(in: 0...255) }
            }
            var ivBytes = Self.keyBytesArg(ivValue)
            let ivBox = NSMutableArray(array: [UInt8](ivBytes))
            _ = ivBox

            let object = JSValue(newObjectIn: self.context)!
            object.setObject(JSValue(object: transformation, in: self.context), forKeyedSubscript: "transformation" as NSString)

            var currentIV: [UInt8]? = ivBytes.isEmpty ? nil : ivBytes

            let setIv: NativeBlock1 = { value in
                let bytes = Self.keyBytesArg(value)
                currentIV = bytes.isEmpty ? nil : bytes
                return object
            }
            object.setObject(setIv, forKeyedSubscript: "setIv" as NSString)

            func process(_ input: JSValue?, decrypt: Bool) -> JSValue {
                let data = Self.cryptoDataArg(input, decrypt: decrypt)
                do {
                    let result = try JSSymmetricCrypto.process(
                        data: data,
                        key: keyBytes,
                        transformation: transformation,
                        iv: currentIV,
                        decrypt: decrypt
                    )
                    return self.bytesValue(result)
                } catch {
                    return self.nativeFailure(error.localizedDescription)
                }
            }

            let encrypt1: NativeBlock1 = { value in
                process(value, decrypt: false)
            }
            let decrypt1: NativeBlock1 = { value in
                process(value, decrypt: true)
            }
            object.setObject(encrypt1, forKeyedSubscript: "encrypt" as NSString)
            object.setObject(decrypt1, forKeyedSubscript: "decrypt" as NSString)

            let encryptBase64: NativeBlock1 = { value in
                let bytes = Self.cryptoDataArg(value, decrypt: false)
                do {
                    let result = try JSSymmetricCrypto.process(data: bytes, key: keyBytes, transformation: transformation, iv: currentIV, decrypt: false)
                    return JSValue(object: JSTextCodec.base64Encode(result), in: self.context)
                } catch {
                    return self.nativeFailure(error.localizedDescription)
                }
            }
            object.setObject(encryptBase64, forKeyedSubscript: "encryptBase64" as NSString)

            let encryptHex: NativeBlock1 = { value in
                let bytes = Self.cryptoDataArg(value, decrypt: false)
                do {
                    let result = try JSSymmetricCrypto.process(data: bytes, key: keyBytes, transformation: transformation, iv: currentIV, decrypt: false)
                    return JSValue(object: JSTextCodec.hexEncode(result), in: self.context)
                } catch {
                    return self.nativeFailure(error.localizedDescription)
                }
            }
            object.setObject(encryptHex, forKeyedSubscript: "encryptHex" as NSString)

            let encryptStr: NativeBlock1 = { value in
                let bytes = Self.cryptoDataArg(value, decrypt: false)
                do {
                    let result = try JSSymmetricCrypto.process(data: bytes, key: keyBytes, transformation: transformation, iv: currentIV, decrypt: false)
                    return JSValue(object: JSTextCodec.string(from: result, charset: "utf-8"), in: self.context)
                } catch {
                    return self.nativeFailure(error.localizedDescription)
                }
            }
            object.setObject(encryptStr, forKeyedSubscript: "encryptStr" as NSString)

            let decryptStr: NativeBlock1 = { value in
                let bytes = Self.cryptoDataArg(value, decrypt: true)
                do {
                    let result = try JSSymmetricCrypto.process(data: bytes, key: keyBytes, transformation: transformation, iv: currentIV, decrypt: true)
                    return JSValue(object: JSTextCodec.string(from: result, charset: "utf-8"), in: self.context)
                } catch {
                    return self.nativeFailure(error.localizedDescription)
                }
            }
            object.setObject(decryptStr, forKeyedSubscript: "decryptStr" as NSString)

            let decryptBase64: NativeBlock1 = { value in
                let bytes = JSTextCodec.base64Decode(Self.stringArg(value)) ?? []
                do {
                    let result = try JSSymmetricCrypto.process(data: bytes, key: keyBytes, transformation: transformation, iv: currentIV, decrypt: true)
                    return self.bytesValue(result)
                } catch {
                    return self.nativeFailure(error.localizedDescription)
                }
            }
            object.setObject(decryptBase64, forKeyedSubscript: "decryptBase64" as NSString)

            let decryptHex: NativeBlock1 = { value in
                let bytes = JSTextCodec.hexDecode(Self.stringArg(value)) ?? []
                do {
                    let result = try JSSymmetricCrypto.process(data: bytes, key: keyBytes, transformation: transformation, iv: currentIV, decrypt: true)
                    return self.bytesValue(result)
                } catch {
                    return self.nativeFailure(error.localizedDescription)
                }
            }
            object.setObject(decryptHex, forKeyedSubscript: "decryptHex" as NSString)
            return object
        }
        java.setObject(createSymmetricCrypto, forKeyedSubscript: "createSymmetricCrypto" as NSString)

        let encryptStr: @convention(block) (JSValue, JSValue, JSValue, JSValue) -> JSValue = { [weak self] dataValue, transformationValue, keyValue, ivValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            do {
                let result = try JSSymmetricCrypto.process(
                    data: JSTextCodec.bytes(from: Self.stringArg(dataValue), charset: "utf-8"),
                    key: Self.keyBytesArg(keyValue),
                    transformation: Self.stringArg(transformationValue),
                    iv: Self.keyBytesArg(ivValue),
                    decrypt: false
                )
                return JSValue(object: JSTextCodec.base64Encode(result), in: self.context)
            } catch {
                return self.nativeFailure(error.localizedDescription)
            }
        }
        java.setObject(encryptStr, forKeyedSubscript: "encryptStr" as NSString)

        let decryptStr: @convention(block) (JSValue, JSValue, JSValue, JSValue) -> JSValue = { [weak self] dataValue, transformationValue, keyValue, ivValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            do {
                let result = try JSSymmetricCrypto.process(
                    data: Self.cryptoDataArg(dataValue, decrypt: true),
                    key: Self.keyBytesArg(keyValue),
                    transformation: Self.stringArg(transformationValue),
                    iv: Self.keyBytesArg(ivValue),
                    decrypt: true
                )
                return JSValue(object: JSTextCodec.string(from: result, charset: "utf-8"), in: self.context)
            } catch {
                return self.nativeFailure(error.localizedDescription)
            }
        }
        java.setObject(decryptStr, forKeyedSubscript: "decryptStr" as NSString)

        let aesEncodeToString: @convention(block) (JSValue, JSValue, JSValue, JSValue) -> JSValue = { [weak self] dataValue, keyValue, transformationValue, ivValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            do {
                let result = try JSSymmetricCrypto.process(
                    data: JSTextCodec.bytes(from: Self.stringArg(dataValue), charset: "utf-8"),
                    key: Self.keyBytesArg(keyValue),
                    transformation: Self.stringArg(transformationValue),
                    iv: Self.keyBytesArg(ivValue),
                    decrypt: false
                )
                return JSValue(object: JSTextCodec.base64Encode(result), in: self.context)
            } catch {
                return self.nativeFailure(error.localizedDescription)
            }
        }
        java.setObject(aesEncodeToString, forKeyedSubscript: "aesEncodeToString" as NSString)

        let aesEncodeToBase64String: @convention(block) (JSValue, JSValue, JSValue, JSValue) -> JSValue = { dataValue, keyValue, transformationValue, ivValue in
            aesEncodeToString(dataValue, keyValue, transformationValue, ivValue)
        }
        java.setObject(aesEncodeToBase64String, forKeyedSubscript: "aesEncodeToBase64String" as NSString)

        let aesDecodeToString: @convention(block) (JSValue, JSValue, JSValue, JSValue) -> JSValue = { [weak self] dataValue, keyValue, transformationValue, ivValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            do {
                let result = try JSSymmetricCrypto.process(
                    data: Self.cryptoDataArg(dataValue, decrypt: true),
                    key: Self.keyBytesArg(keyValue),
                    transformation: Self.stringArg(transformationValue),
                    iv: Self.keyBytesArg(ivValue),
                    decrypt: true
                )
                return JSValue(object: JSTextCodec.string(from: result, charset: "utf-8"), in: self.context)
            } catch {
                return self.nativeFailure(error.localizedDescription)
            }
        }
        java.setObject(aesDecodeToString, forKeyedSubscript: "aesDecodeToString" as NSString)

        let aesDecodeToByteArray: @convention(block) (JSValue, JSValue, JSValue, JSValue) -> JSValue = { [weak self] dataValue, keyValue, transformationValue, ivValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            do {
                let result = try JSSymmetricCrypto.process(
                    data: Self.cryptoDataArg(dataValue, decrypt: true),
                    key: Self.keyBytesArg(keyValue),
                    transformation: Self.stringArg(transformationValue),
                    iv: Self.keyBytesArg(ivValue),
                    decrypt: true
                )
                return self.bytesValue(result)
            } catch {
                return self.nativeFailure(error.localizedDescription)
            }
        }
        java.setObject(aesDecodeToByteArray, forKeyedSubscript: "aesDecodeToByteArray" as NSString)

        // MARK: 签名（RSA 最小可用）

        let createSign: NativeBlock1 = { [weak self] algorithmValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let algorithm = Self.stringArg(algorithmValue)
            let object = JSValue(newObjectIn: self.context)!
            var keyBytes: [UInt8] = []
            var pending: [UInt8] = []
            var verifying = false

            func keyFrom(_ value: JSValue?) -> [UInt8] {
                guard let value else { return [] }
                if value.isObject {
                    if let base64 = value.objectForKeyedSubscript("_keyBase64")?.toString(), !base64.isEmpty {
                        return JSTextCodec.base64Decode(base64) ?? []
                    }
                    if let encoded = value.objectForKeyedSubscript("getEncoded")?.call(withArguments: []) {
                        return Self.bytesArg(encoded)
                    }
                }
                if value.isString {
                    let text = value.toString() ?? ""
                    return JSTextCodec.base64Decode(text) ?? JSTextCodec.bytes(from: text, charset: "utf-8")
                }
                return Self.bytesArg(value)
            }

            let initSign: NativeBlock1 = { value in
                keyBytes = keyFrom(value)
                pending = []
                verifying = false
                return object
            }
            object.setObject(initSign, forKeyedSubscript: "initSign" as NSString)

            let initVerify: NativeBlock1 = { value in
                keyBytes = keyFrom(value)
                pending = []
                verifying = true
                return object
            }
            object.setObject(initVerify, forKeyedSubscript: "initVerify" as NSString)

            let update: NativeBlock1 = { value in
                if value.isString {
                    pending.append(contentsOf: JSTextCodec.bytes(from: value.toString() ?? "", charset: "utf-8"))
                } else {
                    pending.append(contentsOf: Self.bytesArg(value))
                }
                return JSValue(undefinedIn: JSContext.current())
            }
            object.setObject(update, forKeyedSubscript: "update" as NSString)

            let sign: NativeBlock1 = { input in
                var data = pending
                if !input.isUndefined, !input.isNull {
                    data = input.isString ? JSTextCodec.bytes(from: input.toString() ?? "", charset: "utf-8") : Self.bytesArg(input)
                }
                do {
                    let signature = try JSRSA.sign(algorithm: algorithm, keyDER: keyBytes, data: data)
                    return self.bytesValue(signature)
                } catch {
                    return self.nativeFailure(error.localizedDescription)
                }
            }
            object.setObject(sign, forKeyedSubscript: "sign" as NSString)

            let verify: NativeBlock1 = { signatureValue in
                do {
                    let ok = try JSRSA.verify(
                        algorithm: algorithm,
                        keyDER: keyBytes,
                        data: pending,
                        signature: Self.base64OrBytesArg(signatureValue)
                    )
                    return JSValue(bool: ok, in: self.context)
                } catch {
                    return self.nativeFailure(error.localizedDescription)
                }
            }
            object.setObject(verify, forKeyedSubscript: "verify" as NSString)

            let getAlgorithm: NativeBlock0 = {
                JSValue(object: algorithm, in: self.context)
            }
            object.setObject(getAlgorithm, forKeyedSubscript: "getAlgorithm" as NSString)
            _ = verifying
            return object
        }
        java.setObject(createSign, forKeyedSubscript: "createSign" as NSString)

        // MARK: 网络补充

        let ajaxAll: @convention(block) (JSValue) -> JSValue = { [weak self] urlList in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let values = urlList.toArray() ?? []
            let array = JSValue(newArrayIn: self.context)!
            for (index, item) in values.enumerated() {
                let url = JSONValueUtil.text(item)
                if url.isEmpty { continue }
                let response = self.makeResponseValue(url: url, method: "GET", headers: [:], body: nil)
                array.setObject(response, atIndexedSubscript: index)
            }
            return array
        }
        java.setObject(ajaxAll, forKeyedSubscript: "ajaxAll" as NSString)

        let connect: NativeBlock2 = { [weak self] urlValue, headerValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return self.makeResponseValue(url: Self.stringArg(urlValue), method: "GET", headers: self.headerMap(from: headerValue), body: nil)
        }
        java.setObject(connect, forKeyedSubscript: "connect" as NSString)

        let getTxtInUrl: NativeBlock1 = { [weak self] urlValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let url = Self.stringArg(urlValue)
            do {
                let response = try self.http.requestSync(url, timeout: 20)
                return JSValue(object: response.body, in: self.context)
            } catch {
                self.appendLog("java.getTxtInUrl", "失败：\(error.localizedDescription) \(url)")
                return JSValue(object: "", in: self.context)
            }
        }
        java.setObject(getTxtInUrl, forKeyedSubscript: "getTxtInUrl" as NSString)

        // MARK: 文件 / 缓存

        let cacheFile: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] urlValue, saveTimeValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let url = Self.stringArg(urlValue)
            let saveTime = saveTimeValue.isUndefined || saveTimeValue.isNull ? 0 : Self.intArg(saveTimeValue)
            return JSValue(object: self.cacheTextFile(url: url, saveTimeSeconds: saveTime), in: self.context)
        }
        java.setObject(cacheFile, forKeyedSubscript: "cacheFile" as NSString)

        let getFile: NativeBlock1 = { [weak self] pathValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return self.makeFileObject(path: Self.stringArg(pathValue))
        }
        java.setObject(getFile, forKeyedSubscript: "getFile" as NSString)

        let readTxtFile: NativeBlock2 = { [weak self] pathValue, charsetValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let path = Self.stringArg(pathValue)
            let charset = Self.stringArg(charsetValue)
            guard let url = self.resolveCacheURL(path), let data = try? Data(contentsOf: url) else {
                return JSValue(object: "", in: self.context)
            }
            let text = charset.isEmpty ? HTTPClient.decode(data: data, charset: nil) : JSTextCodec.string(from: Array(data), charset: charset)
            return JSValue(object: text, in: self.context)
        }
        java.setObject(readTxtFile, forKeyedSubscript: "readTxtFile" as NSString)

        let readFile: NativeBlock1 = { [weak self] pathValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let url = self.resolveCacheURL(Self.stringArg(pathValue)), let data = try? Data(contentsOf: url) else {
                return JSValue(nullIn: self.context)
            }
            return self.bytesValue(Array(data))
        }
        java.setObject(readFile, forKeyedSubscript: "readFile" as NSString)

        let deleteFile: NativeBlock1 = { [weak self] pathValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let url = self.resolveCacheURL(Self.stringArg(pathValue)) else {
                return JSValue(bool: false, in: self.context)
            }
            try? FileManager.default.removeItem(at: url)
            return JSValue(bool: !FileManager.default.fileExists(atPath: url.path), in: self.context)
        }
        java.setObject(deleteFile, forKeyedSubscript: "deleteFile" as NSString)
        // MARK: ZIP / 压缩包（EPUB、zip 书源）

        let getZipString: NativeBlock2 = { [weak self] sourceValue, entryValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let source = Self.stringArg(sourceValue)
            let entry = Self.stringArg(entryValue)
            guard let payload = self.archiveRead(source: source, entry: entry, isBase64: false) else {
                self.appendLog("java.getZipStringContent", "无法读取压缩包/条目 \(String(source.prefix(120))) \(entry)")
                return JSValue(object: "", in: self.context)
            }
            return JSValue(object: HTTPClient.decode(data: payload, charset: nil), in: self.context)
        }
        java.setObject(getZipString, forKeyedSubscript: "getZipStringContent" as NSString)

        let getZipBytes: NativeBlock2 = { [weak self] sourceValue, entryValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let payload = self.archiveRead(source: Self.stringArg(sourceValue), entry: Self.stringArg(entryValue), isBase64: false) else {
                return JSValue(nullIn: self.context)
            }
            return self.bytesValue(Array(payload))
        }
        java.setObject(getZipBytes, forKeyedSubscript: "getZipByteArrayContent" as NSString)

        let unzipFile: NativeBlock1 = { [weak self] sourceValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let source = Self.stringArg(sourceValue)
            let dest = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("zhijian-js/unzip/\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            guard self.archiveExtractAll(source: source, isBase64: false, to: dest) else {
                self.appendLog("java.unzipFile", "无法解包 \(String(source.prefix(120)))")
                return JSValue(object: "", in: self.context)
            }
            return JSValue(object: dest.path, in: self.context)
        }
        java.setObject(unzipFile, forKeyedSubscript: "unzipFile" as NSString)

        let unsupportedArchive = { (name: String) -> NativeBlock2 in
            { [weak self] _, _ in
                guard let self else { return JSValue(undefinedIn: JSContext.current()) }
                return self.nativeFailure("UnsupportedApi: \(name) 暂未实现（iOS 端未内置 RAR/7z 解码器）")
            }
        }
        java.setObject(unsupportedArchive("getRarStringContent"), forKeyedSubscript: "getRarStringContent" as NSString)
        // MARK: WebView 兜底（@webjs / java.webView*）

        let webView: NativeBlock3 = { [weak self] htmlValue, urlValue, jsValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let html = Self.stringArg(htmlValue)
            let url = Self.stringArg(urlValue)
            let script = Self.stringArg(jsValue)
            let output = HeadlessWebViewEngine.renderSync(
                html: html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : html,
                baseURL: url.isEmpty ? nil : url,
                url: html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !url.isEmpty ? url : nil,
                javaScript: script.isEmpty ? nil : script,
                timeout: 25
            ) ?? ""
            return JSValue(object: output, in: self.context)
        }
        java.setObject(webView, forKeyedSubscript: "webView" as NSString)

        let webViewGetSource: NativeBlock4 = { [weak self] htmlValue, urlValue, jsValue, sourceRegexValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let html = Self.stringArg(htmlValue)
            let url = Self.stringArg(urlValue)
            let script = Self.stringArg(jsValue)
            let sourceRegex = Self.stringArg(sourceRegexValue)
            let output = HeadlessWebViewEngine.renderSync(
                html: html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : html,
                baseURL: url.isEmpty ? nil : url,
                url: html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !url.isEmpty ? url : nil,
                javaScript: script.isEmpty ? nil : script,
                timeout: 25
            ) ?? ""
            guard !sourceRegex.isEmpty else { return JSValue(object: output, in: self.context) }
            return JSValue(object: Self.regexExtract(sourceRegex, from: output) ?? output, in: self.context)
        }
        java.setObject(webViewGetSource, forKeyedSubscript: "webViewGetSource" as NSString)

        let webViewGetOverrideUrl: NativeBlock4 = { [weak self] htmlValue, urlValue, jsValue, _ in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let html = Self.stringArg(htmlValue)
            let url = Self.stringArg(urlValue)
            let script = Self.stringArg(jsValue)
            let output = HeadlessWebViewEngine.renderSync(
                html: html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : html,
                baseURL: url.isEmpty ? nil : url,
                url: html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !url.isEmpty ? url : nil,
                javaScript: script.isEmpty ? "location.href" : script,
                timeout: 25
            ) ?? ""
            return JSValue(object: output.trimmingCharacters(in: .whitespacesAndNewlines), in: self.context)
        }
        java.setObject(webViewGetOverrideUrl, forKeyedSubscript: "webViewGetOverrideUrl" as NSString)

        java.setObject(unsupportedArchive("get7zStringContent"), forKeyedSubscript: "get7zStringContent" as NSString)


        let downloadFile: NativeBlock1 = { [weak self] urlValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let url = Self.stringArg(urlValue)
            do {
                let response = try self.http.requestSync(url, timeout: 30)
                guard response.isOK, let path = self.writeCacheFile(url: url, text: response.body) else {
                    return JSValue(object: "", in: self.context)
                }
                return JSValue(object: path, in: self.context)
            } catch {
                self.appendLog("java.downloadFile", "失败：\(error.localizedDescription) \(url)")
                return JSValue(object: "", in: self.context)
            }
        }
        java.setObject(downloadFile, forKeyedSubscript: "downloadFile" as NSString)

        let getTxtInFolder: NativeBlock1 = { [weak self] pathValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.readTextFolder(Self.stringArg(pathValue)), in: self.context)
        }
        java.setObject(getTxtInFolder, forKeyedSubscript: "getTxtInFolder" as NSString)

        // MARK: 脚本 / 浏览器

        let importScript: NativeBlock1 = { [weak self] pathValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let path = Self.stringArg(pathValue)
            let script: String
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                script = self.cacheTextFile(url: path, saveTimeSeconds: 0)
            } else {
                guard let url = self.resolveCacheURL(path), let data = try? Data(contentsOf: url) else {
                    return self.nativeFailure("importScript: 无法读取 \(path)")
                }
                script = HTTPClient.decode(data: data, charset: nil)
            }
            guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return self.nativeFailure("importScript: \(path) 内容为空")
            }
            self.context.exception = nil
            _ = self.context.evaluateScript(script)
            if let exception = self.context.exception {
                let message = exception.toString() ?? "脚本异常"
                self.context.exception = nil
                return self.nativeFailure("importScript 执行失败：\(message)")
            }
            return JSValue(object: script, in: self.context)
        }
        java.setObject(importScript, forKeyedSubscript: "importScript" as NSString)

        let openUrl: NativeBlock2 = { urlValue, _ in
            let raw = Self.stringArg(urlValue)
            guard !raw.isEmpty, raw.count < 64 * 1024, let url = URL(string: raw) else {
                return JSValue(undefinedIn: JSContext.current())
            }
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
            return JSValue(undefinedIn: JSContext.current())
        }
        java.setObject(openUrl, forKeyedSubscript: "openUrl" as NSString)

        let refreshExplore: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            self.appendLog("java.refreshExplore", "已忽略（引擎层不持有发现页 UI）")
            return JSValue(bool: true, in: self.context)
        }
        java.setObject(refreshExplore, forKeyedSubscript: "refreshExplore" as NSString)

        // WebView 系列：明确抛 unsupported（书源里出现时能给出可读诊断）
        let unsupportedWebView: NativeBlock1 = { [weak self] nameValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let name = Self.stringArg(nameValue).isEmpty ? "webView" : Self.stringArg(nameValue)
            if name == "startBrowser" || name == "startBrowserAwait" {
                // 交互浏览器（验证码/手动登录）：iOS 端通过「登录面板 → 浏览器模式（loginUrl WebView）」完成
                return self.nativeFailure("需要浏览器交互（验证码/手动登录）：请在书源登录面板使用浏览器模式（loginUrl WebView），startBrowser 不支持同步调用")
            }
            if name == "getVerificationCode" {
                return self.nativeFailure("需要图形验证码识别：当前书源需在浏览器模式下手动输入验证码")
            }
            return self.nativeFailure("UnsupportedApi: java.\(name) 需要 WKWebView 执行环境（请改用 @js:/@css:/@xpath: 规则）")
        }
        java.setObject(unsupportedWebView, forKeyedSubscript: "startBrowserAwait" as NSString)
        java.setObject(unsupportedWebView, forKeyedSubscript: "startBrowser" as NSString)
        java.setObject(unsupportedWebView, forKeyedSubscript: "getVerificationCode" as NSString)
        java.setObject(unsupportedWebView, forKeyedSubscript: "queryBase64TTF" as NSString)
        java.setObject(unsupportedWebView, forKeyedSubscript: "queryTTF" as NSString)
    }

    // MARK: - 参数/对象构造辅助

    static func keyBytesArg(_ value: JSValue?) -> [UInt8] {
        guard let value, !value.isUndefined, !value.isNull else { return [] }
        if value.isString { return Array((value.toString() ?? "").utf8) }
        if value.isObject, let base64 = value.objectForKeyedSubscript("_keyBase64")?.toString(), !base64.isEmpty {
            return JSTextCodec.base64Decode(base64) ?? []
        }
        if value.isObject, let bytes = value.objectForKeyedSubscript("_keyBytes"), !bytes.isUndefined {
            return bytesArg(bytes)
        }
        return bytesArg(value)
    }

    /// Cipher 的 data 参数：解密时自动识别 hex / base64 / 原始字节
    static func cryptoDataArg(_ value: JSValue?, decrypt: Bool) -> [UInt8] {
        guard let value, !value.isUndefined, !value.isNull else { return [] }
        if !decrypt {
            if value.isString { return Array((value.toString() ?? "").utf8) }
            return bytesArg(value)
        }
        if value.isString {
            let text = value.toString() ?? ""
            if JSTextCodec.looksLikeHex(text), let bytes = JSTextCodec.hexDecode(text) { return bytes }
            if let bytes = JSTextCodec.base64Decode(text), !bytes.isEmpty { return bytes }
            return Array(text.utf8)
        }
        return bytesArg(value)
    }

    static func percentEncode(_ text: String, charset: String) -> String {
        let bytes = JSTextCodec.bytes(from: text, charset: charset)
        var out = ""
        for byte in bytes {
            let scalar = Character(UnicodeScalar(byte))
            if (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E {
                out.append(scalar)
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    static func percentDecode(_ text: String, charset: String) -> String {
        let pattern = text.replacingOccurrences(of: "+", with: " ")
        var bytes: [UInt8] = []
        let chars = Array(pattern.utf8)
        var index = 0
        while index < chars.count {
            if chars[index] == 0x25, index + 2 < chars.count,
               let high = hexValue(chars[index + 1]), let low = hexValue(chars[index + 2]) {
                bytes.append(high << 4 | low)
                index += 3
            } else {
                bytes.append(chars[index])
                index += 1
            }
        }
        return JSTextCodec.string(from: bytes, charset: charset)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private func makeURLObject(raw: String, base: String) -> JSValue {
        let resolved = base.isEmpty ? raw : RuleURLResolver.resolve(base: base, relative: raw)
        let object = JSValue(newObjectIn: context)!
        let components = URLComponents(string: resolved)
        let fields: [String: String] = [
            "href": resolved,
            "protocol": components?.scheme.map { "\($0):" } ?? "",
            "host": components?.host ?? "",
            "path": components?.path ?? "",
            "query": components?.query.map { "?\($0)" } ?? "",
            "ref": components?.fragment.map { "#\($0)" } ?? "",
            "port": components?.port.map(String.init) ?? ""
        ]
        for (key, value) in fields {
            object.setObject(JSValue(object: value, in: context), forKeyedSubscript: key as NSString)
        }
        let toString: NativeBlock0 = { JSValue(object: resolved, in: self.context) }
        object.setObject(toString, forKeyedSubscript: "toString" as NSString)
        let toExternalForm: NativeBlock0 = { JSValue(object: resolved, in: self.context) }
        object.setObject(toExternalForm, forKeyedSubscript: "toExternalForm" as NSString)
        return object
    }

    private func makeFileObject(path: String) -> JSValue {
        let object = JSValue(newObjectIn: context)!
        let resolved = resolveCacheURL(path)
        object.setObject(JSValue(object: path, in: context), forKeyedSubscript: "path" as NSString)
        object.setObject(JSValue(object: resolved?.lastPathComponent ?? "", in: context), forKeyedSubscript: "name" as NSString)

        let exists: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let resolved else { return JSValue(bool: false, in: self.context) }
            return JSValue(bool: FileManager.default.fileExists(atPath: resolved.path), in: self.context)
        }
        object.setObject(exists, forKeyedSubscript: "exists" as NSString)

        let isFile: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let resolved else { return JSValue(bool: false, in: self.context) }
            var isDirectory: ObjCBool = false
            let ok = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory)
            return JSValue(bool: ok && !isDirectory.boolValue, in: self.context)
        }
        object.setObject(isFile, forKeyedSubscript: "isFile" as NSString)

        let isDirectory: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let resolved else { return JSValue(bool: false, in: self.context) }
            var isDirectory: ObjCBool = false
            let ok = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory)
            return JSValue(bool: ok && isDirectory.boolValue, in: self.context)
        }
        object.setObject(isDirectory, forKeyedSubscript: "isDirectory" as NSString)

        let length: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let size = resolved.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
            return JSValue(double: Double(size), in: self.context)
        }
        object.setObject(length, forKeyedSubscript: "length" as NSString)

        let readText: NativeBlock2 = { [weak self] charsetValue, _ in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let resolved, let data = try? Data(contentsOf: resolved) else {
                return JSValue(object: "", in: self.context)
            }
            let charset = Self.stringArg(charsetValue)
            let text = charset.isEmpty ? HTTPClient.decode(data: data, charset: nil) : JSTextCodec.string(from: Array(data), charset: charset)
            return JSValue(object: text, in: self.context)
        }
        object.setObject(readText, forKeyedSubscript: "readText" as NSString)
        object.setObject(JSValue(object: resolved?.path ?? path, in: context), forKeyedSubscript: "absolutePath" as NSString)

        let delete: NativeBlock0 = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let resolved else { return JSValue(bool: false, in: self.context) }
            try? FileManager.default.removeItem(at: resolved)
            return JSValue(bool: !FileManager.default.fileExists(atPath: resolved.path), in: self.context)
        }
        object.setObject(delete, forKeyedSubscript: "delete" as NSString)
        return object
    }

    // MARK: - 缓存文件系统

    func jsCacheRoot() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("zhijian-js", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func regexExtract(_ pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else {
            return nil
        }
        if match.numberOfRanges > 1 { return (text as NSString).substring(with: match.range(at: 1)) }
        return (text as NSString).substring(with: match.range)
    }

    func resolveCacheURL(_ path: String) -> URL? {
        var raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("file://") {
            return URL(string: raw)
        }
        while raw.hasPrefix("/") { raw.removeFirst() }
        guard !raw.contains("..") else { return nil }
        let root = jsCacheRoot().standardizedFileURL
        let url = root.appendingPathComponent(raw).standardizedFileURL
        guard url.path.hasPrefix(root.path) else { return nil }
        return url
    }

    private func cacheKey(_ url: String) -> String {
        JSTextCodec.hexEncode(JSDigest.digest(algorithm: "MD5", data: Array(url.utf8)))
    }

    func writeCacheFile(url: String, text: String) -> String? {
        let key = cacheKey(url)
        let root = jsCacheRoot()
        let file = root.appendingPathComponent("\(key).txt")
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            try data.write(to: file)
            return file.path.hasPrefix(root.path) ? String(file.path.dropFirst(root.path.count + 1)) : file.lastPathComponent
        } catch {
            appendLog("java.cacheFile", "写入失败：\(error.localizedDescription)")
            return nil
        }
    }

    func cacheTextFile(url: String, saveTimeSeconds: Int) -> String {
        let key = cacheKey(url)
        let root = jsCacheRoot()
        let file = root.appendingPathComponent("\(key).txt")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attributes[.modificationDate] as? Date {
            if saveTimeSeconds <= 0 || Date().timeIntervalSince(modified) < TimeInterval(saveTimeSeconds) {
                if let data = try? Data(contentsOf: file) { return HTTPClient.decode(data: data, charset: nil) }
            }
        }
        do {
            let response = try http.requestSync(url, timeout: 20)
            guard response.isOK else { return "" }
            _ = writeCacheFile(url: url, text: response.body)
            return response.body
        } catch {
            appendLog("java.cacheFile", "下载失败：\(error.localizedDescription) \(url)")
            return ""
        }
    }

    func readTextFolder(_ path: String) -> String {
        guard let folder = resolveCacheURL(path) else { return "" }
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return "" }
        var parts: [String] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let data = try? Data(contentsOf: file) {
                parts.append(HTTPClient.decode(data: data, charset: nil))
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - 登录检查（SourcePipeline 调用）

    /// 执行 `source.loginCheckJs`：绑定 `result` 为 HTTP 响应对象，允许返回字符串/修改 body。
    func applyLoginCheck(_ code: String, to response: EngineHTTPResponse) throws -> EngineHTTPResponse {
        try syncExecute {
            installBindings(RuleBindings(
                result: "",
                key: "",
                page: 1,
                baseURL: response.finalURL,
                title: ""
            ))
            let box = LoginResponseBox(response: response)
            let result = makeLoginResponseValue(box)
            context.setObject(result, forKeyedSubscript: "result" as NSString)
            context.exception = nil
            // loginCheckJs 的惯例是 `return result`（Legado/QiReader 都要求），
            // 顶层 return 在 JSC 脚本里非法，因此含 return 的脚本包进 IIFE。
            let hasReturn = code.range(of: "\\breturn\\b", options: .regularExpression) != nil
            let script = hasReturn ? "(function(){\n\(code)\n})()" : code
            let value = context.evaluateScript(script)
            if let exception = context.exception {
                let message = exception.toString() ?? "loginCheckJs 执行失败"
                context.exception = nil
                throw Self.mapJSError(message)
            }
            guard let value, !value.isUndefined, !value.isNull else {
                return box.response
            }
            var newBody: String?
            if value.isString {
                newBody = value.toString()
            } else if value.isObject {
                if value === result || value.objectForKeyedSubscript("__zhijian_login_response")?.toBool() == true {
                    newBody = box.body
                } else if let text = value.objectForKeyedSubscript("bodyText")?.toString() {
                    newBody = text
                } else if let body = value.objectForKeyedSubscript("body"), body.isString {
                    newBody = body.toString()
                }
            }
            var updated = box.response
            if let newBody { updated.body = newBody }
            return updated
        }
    }

    func makeLoginResponseValue(_ box: LoginResponseBox) -> JSValue {
        let ctx = context
        let object = JSValue(newObjectIn: ctx)!
        object.setObject(JSValue(bool: true, in: ctx), forKeyedSubscript: "__zhijian_login_response" as NSString)
        object.setObject(JSValue(object: box.body, in: ctx), forKeyedSubscript: "bodyText" as NSString)
        object.setObject(JSValue(int32: Int32(box.response.status), in: ctx), forKeyedSubscript: "status" as NSString)
        object.setObject(JSValue(object: box.response.finalURL, in: ctx), forKeyedSubscript: "urlText" as NSString)

        let bodyFn: NativeBlock0 = { JSValue(object: box.body, in: ctx) }
        object.setObject(bodyFn, forKeyedSubscript: "body" as NSString)
        object.setObject(bodyFn, forKeyedSubscript: "text" as NSString)

        let codeFn: NativeBlock0 = { JSValue(int32: Int32(box.response.status), in: ctx) }
        object.setObject(codeFn, forKeyedSubscript: "code" as NSString)
        object.setObject(codeFn, forKeyedSubscript: "statusCode" as NSString)

        let urlFn: NativeBlock0 = { JSValue(object: box.response.finalURL, in: ctx) }
        object.setObject(urlFn, forKeyedSubscript: "url" as NSString)

        let headerFn: NativeBlock1 = { name in
            JSValue(object: box.response.headers[Self.stringArg(name)] ?? "", in: ctx)
        }
        object.setObject(headerFn, forKeyedSubscript: "header" as NSString)

        let headersFn: NativeBlock0 = {
            let headersObject = JSValue(newObjectIn: ctx)!
            for (key, value) in box.response.headers {
                headersObject.setObject(JSValue(object: value, in: ctx), forKeyedSubscript: key as NSString)
            }
            let getHeader: NativeBlock1 = { name in
                JSValue(object: box.response.headers[Self.stringArg(name)] ?? "", in: ctx)
            }
            headersObject.setObject(getHeader, forKeyedSubscript: "get" as NSString)
            headersObject.setObject(getHeader, forKeyedSubscript: "header" as NSString)
            let toMap: NativeBlock0 = { JSValue(object: box.response.headers, in: ctx) }
            headersObject.setObject(toMap, forKeyedSubscript: "toMap" as NSString)
            return headersObject
        }
        object.setObject(headersFn, forKeyedSubscript: "headers" as NSString)

        let setBody: NativeBlock1 = { textValue in
            box.body = Self.stringArg(textValue)
            object.setObject(JSValue(object: box.body, in: ctx), forKeyedSubscript: "bodyText" as NSString)
            return object
        }
        object.setObject(setBody, forKeyedSubscript: "setBody" as NSString)

        let toString: NativeBlock0 = { JSValue(object: box.body, in: ctx) }
        object.setObject(toString, forKeyedSubscript: "toString" as NSString)
        return object
    }
}

/// `loginCheckJs` 执行期间可变的响应盒
final class LoginResponseBox {
    var response: EngineHTTPResponse
    var body: String

    init(response: EngineHTTPResponse) {
        self.response = response
        self.body = response.body
    }
}
