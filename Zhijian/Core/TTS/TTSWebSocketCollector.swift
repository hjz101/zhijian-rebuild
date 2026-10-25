// TTSWebSocketCollector.swift — 收集 WebSocket 音频帧并等待 done/超时
import Foundation

final class TTSWebSocketCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var result: Result<Data, Error>?
    private var closed = false

    func append(_ chunk: Data) {
        lock.lock()
        if result == nil { data.append(chunk) }
        lock.unlock()
    }

    func finish(_ outcome: Result<Data, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        let final: Result<Data, Error>
        switch outcome {
        case .success:
            let payload = data.isEmpty ? ((try? outcome.get()) ?? Data()) : data
            final = payload.isEmpty ? .failure(CollectorError.empty) : .success(payload)
        case .failure(let error):
            final = .failure(error)
        }
        result = final
        let waiter = continuation
        continuation = nil
        lock.unlock()
        waiter?.resume(with: final)
    }

    func closeIfNeeded() {
        lock.lock()
        let alreadyDone = result != nil
        if !alreadyDone { closed = true }
        lock.unlock()
        guard !alreadyDone else { return }
        finish(data.isEmpty ? .failure(CollectorError.closedWithoutAudio) : .success(data))
    }

    func wait() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    enum CollectorError: LocalizedError {
        case empty
        case closedWithoutAudio
        case timeout

        var errorDescription: String? {
            switch self {
            case .empty: return "WebSocket 未返回音频数据"
            case .closedWithoutAudio: return "WebSocket 连接关闭但没有音频帧"
            case .timeout: return "WebSocket 音频流超时"
            }
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
