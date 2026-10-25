// KeychainStore.swift — 轻量 Keychain 封装（GenericPassword，按 service+account 存取）
import Foundation
import Security

enum KeychainStore {
    static let webDAVService = "com.zhijian.reader.webdav"
    static let ttsService = "com.zhijian.reader.tts.login"

    @discardableResult
    static func set(_ value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete(service: service, account: account)
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        if let group = accessGroup { item[kSecAttrAccessGroup as String] = group }
        let status = SecItemAdd(item as CFDictionary, nil)
        #if DEBUG
        if status != errSecSuccess {
            NSLog("[Keychain] add %@/%@ failed %d", service, account, status)
        }
        #endif
        return status == errSecSuccess
    }

    /// 需要 Keychain Sharing entitlement 时设置；无 entitlement 时留空（默认 app 私有组）。
    private static var accessGroup: String? { nil }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
