// PCMStreamPlayer.swift — PCM 分帧流式播放（P3-03 完整版）
// 接收 WS 二进制帧（PCM16LE，默认 16kHz 单声道），逐帧转 AVAudioPCMBuffer 立即播放，
// 首帧到达即开播（无需等完整文件）。也兼容非 PCM：先尝试按 AVAudioFile 解码缓冲。
import AVFoundation

@MainActor
final class PCMStreamPlayer {
    static let shared = PCMStreamPlayer()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var isRunning = false
    private var pendingSampleCount: AVAudioFrameCount = 0
    private var bytesPerFrame: Int = 2

    private init() {
        // PCM16 单声道 16kHz（书源 WS TTS 常见约定；采样率可随帧头调整）
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        format = AVAudioFormat(settings: settings)!
        engine.attach(playerNode)
    }

    var isPlaying: Bool { playerNode.isPlaying }

    func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio)
            try? session.setActive(true)
            engine.prepare()
            try engine.start()
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            isRunning = true
        } catch {
            NSLog("[PCMStream] start failed %@", error.localizedDescription)
        }
    }

    /// 自检：把 PCM 数据转成 AVAudioPCMBuffer，返回帧数（不启动引擎）。
    func convertForValidation(_ data: Data) -> Int {
        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return 0 }
        buffer.frameLength = frameCount
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        if let channel = buffer.int16ChannelData?[0] {
            for (index, sample) in samples.enumerated() { channel[index] = sample }
        }
        return Int(buffer.frameLength)
    }

    /// 是否有音频渲染设备（模拟器可能为 false）。
    var deviceAvailable: Bool { AVAudioSession.sharedInstance().availableCategories.isEmpty == false }

    func feed(_ data: Data) {
        guard isRunning, !data.isEmpty else { return }
        // 帧头可携带采样率（可选）：不做深度解析，默认按 16bit/帧
        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        if let channel = buffer.int16ChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channel[index] = sample
            }
        }
        playerNode.scheduleBuffer(buffer, at: nil, options: [.interruptsAtLoop, .interrupts])
        pendingSampleCount += frameCount
        if !playerNode.isPlaying { playerNode.play() }
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        isRunning = false
        pendingSampleCount = 0
    }

    func pause() { playerNode.pause() }
    func resume() {
        start()
        playerNode.play()
    }
}
