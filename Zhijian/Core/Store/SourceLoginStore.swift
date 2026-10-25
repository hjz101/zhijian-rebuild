// SourceLoginStore.swift — 书源登录态（loginInfo / loginHeader）持久化
import Foundation
import Combine

struct SourceLoginState: Codable, Hashable, Sendable {
    var sourceUrl: String
    var loginInfo: [String: String] = [:]
    var loginHeader: [String: String] = [:]
    var updatedAt: Date = Date()

    var isEmpty: Bool { loginInfo.isEmpty && loginHeader.isEmpty }
}

@MainActor
final class SourceLoginStore: ObservableObject {
    static let shared = SourceLoginStore()

    @Published private(set) var states: [String: SourceLoginState] = [:]
    private let file = "source_login.json"

    private init() {
        states = AppData.load([String: SourceLoginState].self, file) ?? [:]
    }

    func state(for sourceUrl: String) -> SourceLoginState? {
        guard let state = states[sourceUrl], !state.isEmpty else { return nil }
        return state
    }

    func loginInfo(for sourceUrl: String) -> [String: String] {
        states[sourceUrl]?.loginInfo ?? [:]
    }

    func loginHeader(for sourceUrl: String) -> [String: String] {
        states[sourceUrl]?.loginHeader ?? [:]
    }

    func save(sourceUrl: String, loginInfo: [String: String], loginHeader: [String: String]) {
        let state = SourceLoginState(sourceUrl: sourceUrl, loginInfo: loginInfo,
                                     loginHeader: loginHeader, updatedAt: Date())
        if state.isEmpty {
            states.removeValue(forKey: sourceUrl)
        } else {
            states[sourceUrl] = state
        }
        persist()
    }

    func remove(sourceUrl: String) {
        states.removeValue(forKey: sourceUrl)
        persist()
    }

    private func persist() {
        AppData.save(states, file)
    }
}
