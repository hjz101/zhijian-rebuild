// BackupCrypto.swift — .zjbk 加密容器（PBKDF2-HMAC-SHA256 + AES-GCM）
import Foundation
import CryptoKit
import CommonCrypto
import Security

enum BackupCrypto {
    static let magic = Data("ZJBKENC1".utf8)
    static let saltLength = 16
    static let iterations: UInt32 = 120_000
    static let keyLength = 32

    static func isEncrypted(_ data: Data) -> Bool {
        data.count > magic.count + saltLength && data.prefix(magic.count) == magic
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
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw BackupError.encryptionFailed("AES-GCM 封装失败")
        }
        return magic + salt + combined
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard isEncrypted(data) else { throw BackupError.notBackup }
        let salt = data.subdata(in: magic.count..<(magic.count + saltLength))
        let combined = data.subdata(in: (magic.count + saltLength)..<data.count)
        let key = try deriveKey(password: password, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw BackupError.wrongPassword
        }
    }

    static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
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
