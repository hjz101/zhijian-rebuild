// WebDAVConfigStore.swift — WebDAV 配置持久化（JSON 仅存非敏感字段，密码入 Keychain）
import Foundation
import Combine

/// WebDAV 配置仓库。
///
/// P2-04：密码迁移到 Keychain（`com.zhijian.reader.webdav`），`webdav.json` 不再含密码。
/// 首次启动会把旧版 JSON 里的明文密码自动迁移进 Keychain 并清空。
@MainActor
final class WebDAVConfigStore: ObservableObject {
    static let shared = WebDAVConfigStore()

    @Published private(set) var configs: [WebDAVConfig] = []
    @Published var activeConfigID: String? {
        didSet { persist() }
    }

    private struct Snapshot: Codable {
        var configs: [WebDAVConfig] = []
        var activeConfigID: String?
    }

    private let file = "webdav.json"
    private var snapshot: Snapshot

    private init() {
        snapshot = AppData.load(Snapshot.self, file) ?? Snapshot()
        // 迁移：JSON 里的明文密码 → Keychain，然后从 JSON 清空
        var migrated = false
        var hydrated: [WebDAVConfig] = []
        for var config in snapshot.configs {
            let keychainPassword = KeychainStore.get(service: KeychainStore.webDAVService, account: config.id)
            if let keychainPassword, !keychainPassword.isEmpty {
                config.password = keychainPassword
            } else if !config.password.isEmpty {
                KeychainStore.set(config.password, service: KeychainStore.webDAVService, account: config.id)
                config.password = ""
                migrated = true
            }
            hydrated.append(config)
        }
        snapshot.configs = hydrated
        configs = hydrated
        activeConfigID = snapshot.activeConfigID
        if migrated { persist() }
    }

    var activeConfig: WebDAVConfig? {
        guard let activeConfigID else { return nil }
        return configs.first { $0.id == activeConfigID }
    }

    func config(id: String?) -> WebDAVConfig? {
        guard let id else { return nil }
        return configs.first { $0.id == id }
    }

    func add(_ config: WebDAVConfig) {
        var item = config
        if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.id = UUID().uuidString
        }
        if let index = configs.firstIndex(where: { $0.id == item.id }) {
            configs[index] = item
        } else {
            configs.append(item)
        }
        if activeConfigID == nil { activeConfigID = item.id }
        persist()
    }

    func update(_ config: WebDAVConfig) {
        guard let index = configs.firstIndex(where: { $0.id == config.id }) else {
            add(config)
            return
        }
        configs[index] = config
        persist()
    }

    func remove(id: String) {
        configs.removeAll { $0.id == id }
        KeychainStore.delete(service: KeychainStore.webDAVService, account: id)
        if activeConfigID == id { activeConfigID = configs.first?.id }
        persist()
    }

    func remove(_ config: WebDAVConfig) {
        remove(id: config.id)
    }

    func setActive(_ id: String?) {
        activeConfigID = id
    }

    func makeBlank() -> WebDAVConfig {
        WebDAVConfig(
            id: UUID().uuidString,
            name: "我的 WebDAV",
            url: "",
            username: "",
            password: "",
            directory: "ZhijianBackups"
        )
    }

    /// Keychain 不可用（未签名/缺 entitlement）时回退明文，UI 需提示。
    @Published private(set) var usingFallbackStorage = false

    private func persist() {
        // 密码进 Keychain；不可用时回退明文（未签名构建）
        var allKeychain = true
        for config in configs where !config.password.isEmpty {
            if !KeychainStore.set(config.password, service: KeychainStore.webDAVService, account: config.id) {
                allKeychain = false
            }
        }
        usingFallbackStorage = !allKeychain
        let stripped = allKeychain
            ? configs.map { config -> WebDAVConfig in
                var copy = config
                copy.password = ""
                return copy
            }
            : configs
        snapshot.configs = stripped
        snapshot.activeConfigID = activeConfigID
        AppData.save(snapshot, file)
        // 中危修复：明文回退时至少加文件保护（设备解锁前不可读）
        if usingFallbackStorage {
            let url = AppData.root.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path) {
                try? (url as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication,
                                                     forKey: .fileProtectionKey)
            }
        }
    }
}
