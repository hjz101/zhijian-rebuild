// CookieStore.swift — 书源 Cookie 持久化（跨启动/跨书源共享）
import Foundation
import Combine

struct CookieSnapshot: Codable {
    var cookies: [String: [String: String]]
    var updatedAt: Date
}

@MainActor
final class CookieStore: ObservableObject {
    static let shared = CookieStore()

    @Published private(set) var cookies: [String: [String: String]] = [:]
    @Published private(set) var updatedAt: Date?

    private let file = "cookies.json"

    private init() {
        if let snapshot = AppData.load(CookieSnapshot.self, file) {
            cookies = snapshot.cookies
            updatedAt = snapshot.updatedAt
        }
    }

    var cookieCount: Int { cookies.values.reduce(0) { $0 + $1.count } }
    var domains: [String] { cookies.keys.sorted() }

    func snapshot() -> [String: [String: String]] { cookies }

    func merge(_ incoming: [String: [String: String]]) {
        guard !incoming.isEmpty else { return }
        var changed = false
        for (domain, values) in incoming {
            var existing = cookies[domain] ?? [:]
            for (name, value) in values where existing[name] != value {
                existing[name] = value
                changed = true
            }
            cookies[domain] = existing
        }
        guard changed else { return }
        updatedAt = Date()
        persist()
    }

    func set(domain: String, name: String, value: String) {
        let key = domain.lowercased()
        var existing = cookies[key] ?? [:]
        existing[name] = value
        cookies[key] = existing
        updatedAt = Date()
        persist()
    }

    func remove(domain: String) {
        cookies.removeValue(forKey: domain)
        updatedAt = Date()
        persist()
    }

    func clear() {
        cookies = [:]
        updatedAt = Date()
        persist()
    }

    private func persist() {
        AppData.save(CookieSnapshot(cookies: cookies, updatedAt: updatedAt ?? Date()), file)
    }

    nonisolated static func onChange(_ cookies: [String: [String: String]]) {
        Task { @MainActor in CookieStore.shared.merge(cookies) }
    }
}
