// AIConfigStore.swift — LLM 角色识别配置（P3-02，OpenAI 兼容；API Key 存 Keychain）
import Foundation
import Combine

struct AIConfig: Codable, Equatable {
    var endpoint = "https://api.openai.com/v1"
    var model = "gpt-4o-mini"
    var enabled = false
}

@MainActor
final class AIConfigStore: ObservableObject {
    static let shared = AIConfigStore()

    @Published var config: AIConfig {
        didSet { persist() }
    }
    private let file = "ai_config.json"
    private static let keychainAccount = "tts-llm-key"

    private init() {
        config = AppData.load(AIConfig.self, file) ?? AIConfig()
    }

    var apiKey: String {
        KeychainStore.get(service: KeychainStore.ttsService, account: Self.keychainAccount)
            ?? UserDefaults.standard.string(forKey: "tts.ai.key") ?? ""
    }

    func setAPIKey(_ key: String) {
        if key.isEmpty {
            KeychainStore.delete(service: KeychainStore.ttsService, account: Self.keychainAccount)
        } else {
            _ = KeychainStore.set(key, service: KeychainStore.ttsService, account: Self.keychainAccount)
        }
    }

    private func persist() {
        AppData.save(config, file)
    }
}

/// OpenAI 兼容角色识别：从章节文本提取对话角色名（JSON 数组）。
enum LLMRoleDetector {
    /// 批处理：一次请求解析多章角色（{chapters:[{id,roles:[]}]}），减少调用次数。
    static func detectRolesBatch(texts: [(id: String, text: String)], config: AIConfig, apiKey: String) async -> [String: [String]] {
        guard config.enabled, !apiKey.isEmpty, !texts.isEmpty else { return [:] }
        let trimmed = texts.map { String($0.text.prefix(4000)) }
        let endpoint = config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: endpoint + "/chat/completions") else { return [:] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let chaptersJSON = trimmed.enumerated().map { index, text in
            "{\"id\":\"\(texts[index].id)\",\"text\":\(text)"
        }.joined(separator: ",")
        let payload: [String: Any] = [
            "model": config.model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": "为每章小说片段提取说话角色名，返回 JSON：{\"chapters\":[{\"id\":\"章节id\",\"roles\":[\"角色1\"]}]}。没有角色返回空数组。"],
                ["role": "user", "content": "[" + chaptersJSON + "]"]
            ],
            "response_format": ["type": "json_object"]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return [:] }
        request.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let parsed = try? JSONSerialization.jsonObject(with: Data(content.utf8)),
              let root = parsed as? [String: Any],
              let chapters = root["chapters"] as? [[String: Any]] else { return [:] }
        var result: [String: [String]] = [:]
        for chapter in chapters {
            guard let id = chapter["id"] as? String,
                  let roles = chapter["roles"] as? [String] else { continue }
            result[id] = roles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 12 }
        }
        return result
    }
    static func detectRoles(text: String, config: AIConfig, apiKey: String) async -> [String] {
        guard config.enabled, !apiKey.isEmpty else { return [] }
        let trimmed = String(text.prefix(4000))
        guard !trimmed.isEmpty else { return [] }
        let endpoint = config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: endpoint + "/chat/completions") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": config.model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": "从小说片段中提取所有说话的角色名，只返回 JSON 字符串数组，如 [\"阿禾\",\"老人\"]。没有则返回 []。"],
                ["role": "user", "content": trimmed]
            ],
            "response_format": ["type": "json_object"]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return [] }
        request.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let parsed = try? JSONSerialization.jsonObject(with: Data(content.utf8)),
              let array = parsed as? [Any] else { return [] }
        return array.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 12 }
    }
}
