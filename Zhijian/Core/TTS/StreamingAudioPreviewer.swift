// StreamingAudioPreviewer.swift — AVAudioEngine 流式预览播放器（P3-03）
// 用 AVAudioEngine + AVAudioPlayerNode 播放，支持暂停/继续；数据需先解码（mp3/wav/m4a），
// 解码后就绪即开始播放，首句延迟与文件头大小相关（真实 PCM 流式需后端分帧，见 BACKLOG）。
import AVFoundation

@MainActor
final class StreamingAudioPreviewer {
    static let shared = StreamingAudioPreviewer()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var isPrepared = false

    private init() {
        engine.attach(playerNode)
    }

    var isPlaying: Bool { playerNode.isPlaying }

    func load(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        audioFile = file
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
        isPrepared = true
    }

    func play() {
        guard isPrepared, let audioFile else { return }
        if playerNode.isPlaying { playerNode.stop() }
        playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
            DispatchQueue.main.async { self?.playerNode.stop() }
        }
        playerNode.play()
    }

    func pause() {
        playerNode.pause()
    }

    func resume() {
        guard isPrepared else { return }
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
    }

    func dispose() {
        playerNode.stop()
        engine.stop()
        audioFile = nil
        isPrepared = false
    }
}
