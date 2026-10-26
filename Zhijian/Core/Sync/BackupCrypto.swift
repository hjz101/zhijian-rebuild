// BackupCrypto.swift — .zjbk 加密容器（PBKDF2-HMAC-SHA256 + AES-GCM）
import Foundation
import CryptoKit
import CommonCrypto
import Security

enum BackupCrypto {
    static let magic = Data("ZJBKENC2".utf8)
    static let legacyMagic = Data("ZJBKENC1".utf8)
    static let saltLength = 16
    /// OWASP 2026 建议：PBKDF2-HMAC-SHA256 600k+（新备份用）
    static let iterations: UInt32 = 600_000
    /// 旧版 120k（兼容旧备份解密）
    static let legacyIterations: UInt32 = 120_000
    static let keyLength = 32

    static func isEncrypted(_ data: Data) -> Bool {
        data.count > magic.count + saltLength
            && (data.prefix(magic.count) == magic || data.prefix(legacyMagic.count) == legacyMagic)
    }

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { bytes -> Int32 in
            guard let base = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, saltLength, base)
        }
        guard status == errSecSuccess else {
            throw BackupError.encryptionFailed("生成随机盐失败")
        }
        let key = try deriveKey(password: password, salt: salt)
        // AAD 绑定 magic（格式标识），防重排/篡改
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: magic)
        guard let combined = sealed.combined else {
            throw BackupError.encryptionFailed("AES-GCM 封装失败")
        }
        return magic + salt + combined
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard isEncrypted(data) else { throw BackupError.notBackup }
        let isLegacy = data.prefix(legacyMagic.count) == legacyMagic
        let headerCount = isLegacy ? legacyMagic.count : magic.count
        let salt = data.subdata(in: headerCount..<(headerCount + saltLength))
        let combined = data.subdata(in: (headerCount + saltLength)..<data.count)
        let aad = isLegacy ? legacyMagic : magic
        // 新格式 600k；旧格式 120k
        do {
            let key = try deriveKey(password: password, salt: salt, iterations: isLegacy ? legacyIterations : iterations)
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            // 兼容：新格式备份在旧设备/旧实现上可能用 120k 加密过（极少见），尝试回退
            if !isLegacy {
                if let key = try? deriveKey(password: password, salt: salt, iterations: legacyIterations),
                   let box = try? AES.GCM.SealedBox(combined: combined),
                   let opened = try? AES.GCM.open(box, using: key, authenticating: legacyMagic) {
                    return opened
                }
            }
            throw BackupError.wrongPassword
        }
    }

    static func deriveKey(password: String, salt: Data, iterations: UInt32 = iterations) throws -> SymmetricKey {
        let passwordBytes: [Int8] = Array(password.utf8).map { Int8(bitPattern: $0) }
        let saltBytes: [UInt8] = Array(salt)
        var keyBytes = [UInt8](repeating: 0, count: keyLength)
        let status: Int32 = passwordBytes.withUnsafeBufferPointer { passwordBuffer in
            saltBytes.withUnsafeBufferPointer { saltBuffer in
                keyBytes.withUnsafeMutableBufferPointer { keyBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress, passwordBuffer.count,
                        saltBuffer.baseAddress, saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        keyBuffer.baseAddress, keyBuffer.count
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.encryptionFailed("PBKDF2 派生密钥失败（\(status)）")
        }
        return SymmetricKey(data: Data(keyBytes))
    }

}
