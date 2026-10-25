// ProxySettingsStore.swift — 代理设置（P3-07：HTTP/SOCKS 代理，仅本 App 生效）
import Foundation
import Combine

@MainActor
final class ProxySettingsStore: ObservableObject {
    static let shared = ProxySettingsStore()

    @Published var enabled: Bool {
        didSet { persist(); HTTPClient.applyProxy(proxy) }
    }
    @Published var host: String {
        didSet { persist(); HTTPClient.applyProxy(proxy) }
    }
    @Published var port: String {
        didSet { persist(); HTTPClient.applyProxy(proxy) }
    }
    @Published var isSOCKS: Bool {
        didSet { persist(); HTTPClient.applyProxy(proxy) }
    }

    private let file = "proxy_settings.json"
    private struct Snapshot: Codable {
        var enabled = false
        var host = ""
        var port = "8080"
        var isSOCKS = false
    }

    var proxy: (host: String, port: Int, socks: Bool)? {
        guard enabled, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let portValue = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)), portValue > 0 else { return nil }
        return (host.trimmingCharacters(in: .whitespacesAndNewlines), portValue, isSOCKS)
    }

    private init() {
        let snapshot = AppData.load(Snapshot.self, file) ?? Snapshot()
        enabled = snapshot.enabled
        host = snapshot.host
        port = snapshot.port
        isSOCKS = snapshot.isSOCKS
        HTTPClient.applyProxy(proxy)
    }

    private func persist() {
        AppData.save(Snapshot(enabled: enabled, host: host, port: port, isSOCKS: isSOCKS), file)
    }
}
