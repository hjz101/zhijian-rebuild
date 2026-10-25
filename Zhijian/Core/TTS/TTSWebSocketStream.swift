// TTSWebSocketStream.swift — URLSessionWebSocketTask 流式 TTS 骨架
//
// 当前不接入 UI：HTTP TTS 的 WebSocket 模式需要源编写约定
// （java.webSocket({url, headers, send, onMessage…})），先保留可用的连接/收发骨架，
// 后续把 `onAudio` 接到 HTTPTTSDriver 的流式缓存与播放器即可。
import Foundation

struct TTSWebSocketConfiguration: Sendable {
    var url: String
    var headers: [String: String] = [:]
    /// 连接成功后要发送的首帧（通常是 speakText）
    var send: String?
    var contentType: String?
    var connectTimeout: TimeInterval = 12
    var receiveTimeout: TimeInterval = 30
    var maxAudioBytes: Int = 16 * 1024 * 1024
}

/// 极简 WebSocket 音频流。
///
/// 服务端约定的二进制帧直接交给 `onAudio`；JSON 文本帧按
/// `{"type":"audio|send|state|done|error", ...}` 解析，音频字段支持 base64。
final class TTSWebSocketStream: NSObject, @unchecked Sendable {

    enum StreamError: LocalizedError {
        case invalidURL(String)
        case notConnected
        case tooLarge(Int)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let value): return "WebSocket URL 非法：\(value)"
            case .notConnected: return "WebSocket 尚未连接"
            case .tooLarge(let bytes): return "WebSocket 音频帧过大：\(bytes) 字节"
            case .server(let message): return "WebSocket 服务端错误：\(message)"
            }
        }
    }

    var onAudio: ((Data) -> Void)?
    var onState: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onClosed: (() -> Void)?

    private let configuration: TTSWebSocketConfiguration
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var receivedBytes = 0

    init(configuration: TTSWebSocketConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = configuration.connectTimeout
            self.session = URLSession(configuration: config)
        }
        super.init()
    }

    // MARK: 生命周期

    func connect() throws {
        guard let url = URL(string: configuration.url) else {
            throw StreamError.invalidURL(configuration.url)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = configuration.connectTimeout
        for (key, value) in configuration.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        onState?("connected")

        if let send = configuration.send, !send.isEmpty {
            Task { [weak self] in
                do { try await self?.send(text: send) }
                catch { self?.onError?(error.localizedDescription) }
            }
        }
        startReceiveLoop()
    }

    func send(text: String) async throws {
        guard let task else { throw StreamError.notConnected }
        try await task.send(.string(text))
    }

    func send(data: Data) async throws {
        guard let task else { throw StreamError.notConnected }
        try await task.send(.data(data))
    }

    func close(reason: String? = nil) {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .normalClosure, reason: reason?.data(using: .utf8))
        task = nil
        onClosed?()
    }

    // MARK: 接收

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let message = try await self.receiveOnce() else { break }
                    self.handle(message)
                } catch {
                    if !Task.isCancelled { self.onError?(error.localizedDescription) }
                    break
                }
            }
            self.onClosed?()
        }
    }

    private func receiveOnce() async throws -> URLSessionWebSocketTask.Message? {
        guard let task else { return nil }
        return try await task.receive()
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            appendAudio(data)
        case .string(let text):
            handleText(text)
        @unknown default:
            break
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 非 JSON 文本帧当作状态帧
            onState?(text)
            return
        }
        let type = (object["type"] as? String)?.lowercased() ?? ""
        switch type {
        case "audio":
            if let base64 = object["audio"] as? String, let audio = Data(base64Encoded: base64) {
                appendAudio(audio)
            } else if let base64 = object["base64"] as? String, let audio = Data(base64Encoded: base64) {
                appendAudio(audio)
            }
        case "send":
            if let next = object["text"] as? String {
                Task { [weak self] in
                    do { try await self?.send(text: next) }
                    catch { self?.onError?(error.localizedDescription) }
                }
            }
        case "state":
            onState?(object["state"] as? String ?? text)
        case "done":
            onState?("done")
        case "error":
            onError?(object["message"] as? String ?? text)
        default:
            onState?(text)
        }
    }

    private func appendAudio(_ data: Data) {
        receivedBytes += data.count
        if receivedBytes > configuration.maxAudioBytes {
            onError?(StreamError.tooLarge(receivedBytes).localizedDescription)
            close(reason: "audio too large")
            return
        }
        onAudio?(data)
    }
}
