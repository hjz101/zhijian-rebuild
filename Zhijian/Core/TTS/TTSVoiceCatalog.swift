// TTSVoiceCatalog.swift — 系统语音目录 + 语音/多角色偏好
import Foundation
import AVFoundation

/// 供设置页展示的系统语音（只列中文语音，增强/精品优先）。
struct TTSVoiceOption: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var language: String
    var qualityLabel: String
}

enum TTSVoiceCatalog {

    static func chineseVoices() -> [TTSVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("zh") }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { voice in
                let quality: String
                switch voice.quality {
                case .premium: quality = "精品"
                case .enhanced: quality = "增强"
                default: quality = "标准"
                }
                return TTSVoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    qualityLabel: quality
                )
            }
    }

    static func voice(identifier: String?) -> AVSpeechSynthesisVoice? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(identifier: identifier)
    }

    /// 自动选择：增强/精品中文普通话优先，否则系统 zh-CN。
    static func defaultVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("zh") }
        if let best = voices.first(where: { $0.language == "zh-CN" && $0.quality == .premium })
            ?? voices.first(where: { $0.language == "zh-CN" && $0.quality == .enhanced })
            ?? voices.first(where: { $0.language == "zh-CN" }) {
            return best
        }
        return AVSpeechSynthesisVoice(language: "zh-CN") ?? voices.first
    }
}

/// 持久化的朗读偏好（AppData/tts_runtime.json）。
struct TTSVoicePreferences: Codable, Equatable, Sendable {
    var rate: Double = 0.5
    var multiRoleEnabled: Bool = true
    var narratorVoiceID: String?
    var dialogueVoiceID: String?
    var dialogueRateFactor: Double = 1.0
    var selectedSourceID: String?
    /// 角色名 → 系统语音 identifier（智能角色识别后逐角色分配）
    var characterVoices: [String: String] = [:]
    /// 最近一章识别到的角色名
    var recognizedCharacters: [String] = []
    /// 新角色自动分配不同系统语音
    var autoCharacterVoices: Bool = true
}

/// 登录态 / 源变量 / 偏好的轻量运行时存储。
/// 说明：登录 Header 目前由用户手动填写（TTSConfigView），完整 loginUrl + loginUi +
/// loginCheckJs 浏览器登录流程属于后续能力，这里先保留读写结构。
@MainActor
final class TTSRuntimeStore {
    static let shared = TTSRuntimeStore()

    private struct Snapshot: Codable {
        var preferences = TTSVoicePreferences()
        var loginHeaders: [String: String] = [:]
        var sourceVariables: [String: String] = [:]
    }

    private let file = "tts_runtime.json"
    private var snapshot: Snapshot

    private init() {
        snapshot = AppData.load(Snapshot.self, file) ?? Snapshot()
    }

    var preferences: TTSVoicePreferences {
        get { snapshot.preferences }
        set {
            snapshot.preferences = newValue
            persist()
        }
    }

    func loginHeader(for sourceID: String) -> String {
        snapshot.loginHeaders[sourceID] ?? ""
    }

    func setLoginHeader(_ header: String, for sourceID: String) {
        if header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshot.loginHeaders.removeValue(forKey: sourceID)
        } else {
            snapshot.loginHeaders[sourceID] = header
        }
        persist()
    }

    func sourceVariable(for sourceID: String) -> String {
        snapshot.sourceVariables[sourceID] ?? ""
    }

    func setSourceVariable(_ value: String, for sourceID: String) {
        if value.isEmpty {
            snapshot.sourceVariables.removeValue(forKey: sourceID)
        } else {
            snapshot.sourceVariables[sourceID] = value
        }
        persist()
    }

    func removeRuntime(for sourceID: String) {
        snapshot.loginHeaders.removeValue(forKey: sourceID)
        snapshot.sourceVariables.removeValue(forKey: sourceID)
        persist()
    }

    private func persist() {
        AppData.save(snapshot, file)
    }
}
