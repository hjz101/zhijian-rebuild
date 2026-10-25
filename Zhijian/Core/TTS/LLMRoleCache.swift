// LLMRoleCache.swift — LLM 角色识别结果缓存（章节文本哈希）
import Foundation

@MainActor
final class LLMRoleCache {
    static let shared = LLMRoleCache()
    private var store: [String: [String]] = [:]
    private var order: [String] = []
    private let limit = 60

    func cached(_ key: String) -> [String]? { store[key] }

    func put(_ roles: [String], key: String) {
        store[key] = roles
        order.append(key)
        if order.count > limit {
            let removed = order.removeFirst()
            store.removeValue(forKey: removed)
        }
    }
}
