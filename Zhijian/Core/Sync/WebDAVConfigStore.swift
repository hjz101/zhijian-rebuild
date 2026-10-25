// WebDAVConfigStore.swift — WebDAV 配置持久化（Application Support/Zhijian/webdav.json）
import Foundation
import Combine

/// WebDAV 配置仓库。
///
/// ⚠️ 密码当前**明文**保存在 Application Support（不是 Keychain），与旧版行为一致；
/// 设置页需要显式提示用户。后续可迁移到 Keychain。
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
        configs = snapshot.configs
        activeConfigID = snapshot.activeConfigID
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

    private func persist() {
        snapshot.configs = configs
        snapshot.activeConfigID = activeConfigID
        AppData.save(snapshot, file)
    }
}
