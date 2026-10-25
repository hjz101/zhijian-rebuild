// TTSController.swift — 朗读控制器：系统 AVSpeechSynthesizer + HTTP TTS + 多角色 + 锁屏控制
import Foundation
import AVFoundation
import MediaPlayer
import Combine

/// 统一朗读入口。
///
/// 使用方式（阅读页）：
/// ```swift
/// env.tts.onChapterFinished = { loadNextChapterAndPlay() }
/// env.tts.play(text: chapter.text, bookTitle: book.title, chapterTitle: chapter.title)
/// ```
/// 系统朗读与 HTTP TTS 共用句级队列；HTTP 模式按句合成并缓存到 Caches，
/// 失败连续 3 句后停止，单句失败会用系统语音兜底。
@MainActor
final class TTSController: NSObject, ObservableObject, TTSControlling {

    // MARK: - 对外状态

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var bookTitle = ""
    @Published private(set) var chapterTitle = ""
    @Published private(set) var currentSentence = ""
    @Published private(set) var currentSegmentIndex = 0
    @Published private(set) var segmentCount = 0
    @Published private(set) var currentRole: TTSRole = .narrator
    @Published private(set) var currentRoleName: String?
    @Published private(set) var currentSourceName = "系统朗读"
    @Published private(set) var lastError: String?

    /// 0.2–1.0，对应 AVSpeechUtterance.rate；HTTP 源的 `{{speakSpeed}}` = Int(rate * 10)。
    @Published var rate: Float = 0.5 {
        didSet {
            let clamped = min(max(rate, 0.2), 1.0)
            if clamped != rate {
                rate = clamped
                return
            }
            persistPreferences()
            restartSystemSentenceForRateChangeIfNeeded()
        }
    }

    /// 多角色：引号内为对话，其余为旁白；对话可使用不同系统语音/语速。
    @Published var multiRoleEnabled: Bool = true {
        didSet { persistPreferences() }
    }

    /// nil = 自动选择中文增强/精品语音。
    @Published var narratorVoiceID: String? {
        didSet { persistPreferences() }
    }

    /// nil = 自动挑一个不同于旁白的中文语音；没有第二个语音时复用旁白。
    @Published var dialogueVoiceID: String? {
        didSet { persistPreferences() }
    }

    /// 对话语速倍率（0.7–1.3），用于旁白/对话音色区分；HTTP 模式同样生效。
    @Published var dialogueRateFactor: Double = 1.0 {
        didSet {
            let clamped = min(max(dialogueRateFactor, 0.7), 1.3)
            if clamped != dialogueRateFactor {
                dialogueRateFactor = clamped
                return
            }
            persistPreferences()
        }
    }

    /// 角色名 → 系统语音（智能角色识别后逐角色分配）。
    @Published var characterVoices: [String: String] = [:] {
        didSet { persistPreferences() }
    }

    /// 新角色自动分配不同系统语音。
    @Published var autoCharacterVoices: Bool = true {
        didSet { persistPreferences() }
    }

    /// 最近一章识别到的角色名。
    @Published private(set) var recognizedCharacters: [String] = []

    /// 当前句对应的角色名（旁白为 nil）。
    @Published private(set) var currentCharacterName: String?

    /// 当前句在章节全文中的 UTF-16 范围（供阅读器高亮/自动翻页）。
    @Published private(set) var currentSegmentRange: NSRange?

    /// nil = 系统朗读；否则为 TTSSourceStore 中的 HTTP TTS 源 id。
    @Published var selectedSourceID: String? {
        didSet {
            persistPreferences()
            refreshSourceName()
            if (isSpeaking || isPaused) && oldValue != selectedSourceID {
                stop()
            }
        }
    }

    /// 一章读完（自然结束）时回调，供阅读器自动加载下一章。
    var onChapterFinished: (() -> Void)?
    /// 句级进度：(当前句下标, 总句数)。
    var onProgress: ((Int, Int) -> Void)?

    /// 供 UI 观察的 HTTP 源列表。
    let ttsSources = TTSSourceStore.shared

    // MARK: - 私有状态

    private let runtime = TTSRuntimeStore.shared
    private let driver = HTTPTTSDriver.shared
    private let synthesizer = AVSpeechSynthesizer()
    private let speechBridge = SpeechBridge()
    private var cancellables = Set<AnyCancellable>()
    private var segments: [TTSSegment] = []
    private var segmentRanges: [NSRange] = []
    private var index = 0
    private var generation = 0
    private var playbackTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var currentUtterance: AVSpeechUtterance?
    private var systemWaitContinuation: CheckedContinuation<Bool, Never>?
    private var remoteCommandsConfigured = false
    private var interruptionObserver: NSObjectProtocol?
    private var cachedAutoDialogueVoiceID: String??

    // MARK: - 生命周期

    override init() {
        super.init()
        let preferences = runtime.preferences
        rate = Float(preferences.rate)
        multiRoleEnabled = preferences.multiRoleEnabled
        narratorVoiceID = preferences.narratorVoiceID
        dialogueVoiceID = preferences.dialogueVoiceID
        dialogueRateFactor = preferences.dialogueRateFactor
        characterVoices = preferences.characterVoices
        autoCharacterVoices = preferences.autoCharacterVoices
        recognizedCharacters = preferences.recognizedCharacters
        selectedSourceID = preferences.selectedSourceID

        synthesizer.delegate = speechBridge
        speechBridge.onFinish = { [weak self] utterance in
            Task { @MainActor [weak self] in
                self?.handleSpeechFinished(utterance)
            }
        }
        configureRemoteCommands()
        installInterruptionObserver()
        refreshSourceName()

        // 设置页增删 TTS 源时，让迷你条/菜单刷新
        ttsSources.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    // MARK: - 播放控制

    /// 从第一句开始朗读一段文本（章节正文）。
    func play(
        text: String,
        bookTitle: String? = nil,
        chapterTitle: String? = nil,
        startSegmentIndex: Int = 0
    ) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            lastError = "没有可朗读的文本"
            return
        }
        let split = TTSScriptSegmenter.segments(
            cleaned,
            maxLength: TTSScriptSegmenter.defaultMaxSentenceLength,
            splitRoles: multiRoleEnabled
        )
        guard !split.isEmpty else {
            lastError = "没有可朗读的文本"
            return
        }

        stopInternal(clearSession: true)
        if let bookTitle { self.bookTitle = bookTitle }
        if let chapterTitle { self.chapterTitle = chapterTitle }
        segments = split
        segmentRanges = Self.ranges(for: split, in: cleaned)
        let names = Array(Set(split.compactMap(\.characterName))).sorted()
        recognizedCharacters = names
        if autoCharacterVoices { assignCharacterVoices(for: names) }
        segmentCount = split.count
        index = min(max(startSegmentIndex, 0), split.count - 1)
        currentSegmentIndex = index
        segmentCount = split.count
        isSpeaking = true
        isPaused = false
        lastError = nil
        activateAudioSession()
        updateNowPlaying()

        if let source = selectedHTTPSource {
            currentSourceName = source.name
            startHTTPPlayback(source: source)
        } else {
            currentSourceName = "系统朗读"
            updateSegmentState(segments[index])
            speakSystem(segments[index])
        }
    }

    /// TTSControlling：启动后立即返回，进度/结束通过 published 状态与 onChapterFinished 通知。
    func speak(_ text: String) async {
        play(text: text)
    }

    func pause() {
        guard isActive, !isPaused else { return }
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
        audioPlayer?.pause()
        isPaused = true
        isSpeaking = false
        updateNowPlaying()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        isSpeaking = true
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else if selectedHTTPSource == nil,
                  currentUtterance == nil && audioPlayer == nil,
                  segments.indices.contains(index) {
            // 状态丢失（例如切后台）时重读当前句
            updateSegmentState(segments[index])
            speakSystem(segments[index])
        }
        updateNowPlaying()
    }

    func toggle() {
        if isPaused { resume() } else if isSpeaking { pause() } else { /* 没有可恢复内容 */ }
    }

    func stop() {
        stopInternal(clearSession: true)
    }

    func setRate(_ value: Float) {
        rate = min(max(value, 0.2), 1.0)
    }

    func skipForward() {
        seek(to: index + 1)
    }

    func skipBackward() {
        seek(to: index - 1)
    }

    /// 切换系统朗读 / HTTP 源；播放中切换会停止当前朗读。
    func selectSource(_ sourceID: String?) {
        selectedSourceID = sourceID
    }

    var availableSources: [HttpTTS] { ttsSources.enabledSources }

    var isActive: Bool { isSpeaking || isPaused }

    var progress: Double {
        guard segmentCount > 0 else { return 0 }
        return Double(currentSegmentIndex) / Double(segmentCount)
    }

    // MARK: - 系统语音

    private func speakSystem(_ segment: TTSSegment) {
        guard segments.indices.contains(index) else { return }
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = voice(for: segment)
        utterance.rate = systemRate(for: segment)
        utterance.pitchMultiplier = pitch(for: segment)
        utterance.postUtteranceDelay = 0.04
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    /// 系统中文语音数量有限时，用音高进一步区分不同角色。
    private func pitch(for segment: TTSSegment) -> Float {
        guard multiRoleEnabled, segment.role == .dialogue,
              let name = segment.characterName,
              let index = recognizedCharacters.firstIndex(of: name) else { return 1.0 }
        let offsets: [Float] = [1.0, 0.90, 1.10, 0.95, 1.05, 0.86, 1.14]
        return offsets[index % offsets.count]
    }

    private func systemRate(for segment: TTSSegment) -> Float {
        let base = segment.role == .dialogue && multiRoleEnabled
            ? Double(rate) * dialogueRateFactor
            : Double(rate)
        return Float(min(max(base, 0.2), 1.0))
    }

    private func voice(for segment: TTSSegment) -> AVSpeechSynthesisVoice? {
        guard multiRoleEnabled, segment.role == .dialogue else {
            return narratorVoice()
        }
        if let name = segment.characterName,
           let id = characterVoices[name],
           let voice = TTSVoiceCatalog.voice(identifier: id) {
            return voice
        }
        if let id = dialogueVoiceID, let voice = TTSVoiceCatalog.voice(identifier: id) {
            return voice
        }
        return autoDialogueVoice()
    }

    /// 为识别到的角色按顺序分配不同中文语音；已有映射保持不变。
    private func assignCharacterVoices(for names: [String]) {
        guard !names.isEmpty else { return }
        let narratorID = narratorVoice()?.identifier
        let candidates = TTSVoiceCatalog.chineseVoices().map(\.id).filter { $0 != narratorID }
        guard !candidates.isEmpty else { return }
        var used = Set(characterVoices.values)
        var changed = false
        for (offset, name) in names.enumerated() where characterVoices[name] == nil {
            let preferred = candidates[offset % candidates.count]
            let choice = candidates.first { !used.contains($0) } ?? preferred
            characterVoices[name] = choice
            used.insert(choice)
            changed = true
        }
        if changed { persistPreferences() }
    }

    private func narratorVoice() -> AVSpeechSynthesisVoice? {
        if let id = narratorVoiceID, let voice = TTSVoiceCatalog.voice(identifier: id) {
            return voice
        }
        return TTSVoiceCatalog.defaultVoice()
    }

    private func autoDialogueVoice() -> AVSpeechSynthesisVoice? {
        if let cached = cachedAutoDialogueVoiceID {
            if let id = cached { return TTSVoiceCatalog.voice(identifier: id) }
            return narratorVoice()
        }
        let narratorID = narratorVoice()?.identifier
        let option = TTSVoiceCatalog.chineseVoices().first { $0.id != narratorID }
        cachedAutoDialogueVoiceID = option?.id
        if let id = option?.id { return TTSVoiceCatalog.voice(identifier: id) }
        return narratorVoice()
    }

    private func handleSpeechFinished(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        guard isActive else { return }

        if let continuation = systemWaitContinuation {
            systemWaitContinuation = nil
            continuation.resume(returning: true)
            return
        }
        advanceAfterSystemSegment()
    }

    private func advanceAfterSystemSegment() {
        guard isActive else { return }
        if index + 1 < segments.count {
            index += 1
            updateSegmentState(segments[index])
            speakSystem(segments[index])
            updateNowPlaying()
        } else {
            finishChapter()
        }
    }

    private func speakSystemAndWait(_ segment: TTSSegment, generation gen: Int) async -> Bool {
        guard gen == generation else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            systemWaitContinuation = continuation
            speakSystem(segment)
        }
    }

    // MARK: - HTTP TTS

    private var selectedHTTPSource: HttpTTS? {
        guard let id = selectedSourceID, !id.isEmpty else { return nil }
        return ttsSources.source(id: id)
    }

    private func startHTTPPlayback(source: HttpTTS) {
        let gen = generation
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.playHTTPSegments(source: source, generation: gen)
        }
    }

    private func playHTTPSegments(source: HttpTTS, generation gen: Int) async {
        if source.url.lowercased().hasPrefix("ws://") || source.url.lowercased().hasPrefix("wss://") {
            await playWebSocketSegments(source: source, generation: gen)
            return
        }
        var consecutiveFailures = 0

        while segments.indices.contains(index) {
            guard gen == generation, isActive else { return }
            await waitWhilePaused(generation: gen)
            guard gen == generation, isActive else { return }

            let segment = segments[index]
            updateSegmentState(segment)
            updateNowPlaying()

            do {
                let effectiveRate = effectiveHTTPRate(for: segment)
                let file = try await driver.audioFile(
                    for: segment.text,
                    source: source,
                    rate: effectiveRate,
                    loginHeader: runtime.loginHeader(for: source.id),
                    sourceVariable: runtime.sourceVariable(for: source.id)
                )
                try Task.checkCancellation()
                guard gen == generation else { return }
                await waitWhilePaused(generation: gen)
                guard gen == generation, isActive else { return }
                let completed = try await playAudioFile(file, generation: gen)
                guard completed, gen == generation else { return }
                consecutiveFailures = 0
                lastError = nil
            } catch is CancellationError {
                return
            } catch {
                if gen != generation || Task.isCancelled { return }
                consecutiveFailures += 1
                lastError = error.localizedDescription
                if consecutiveFailures >= 3 {
                    isSpeaking = false
                    isPaused = false
                    playbackTask = nil
                    updateNowPlaying(completed: true)
                    deactivateAudioSession()
                    return
                }
                // 单句失败：用系统语音兜底，继续后续 HTTP 句
                let ok = await speakSystemAndWait(segment, generation: gen)
                guard ok, gen == generation else { return }
            }

            guard gen == generation else { return }
            if index + 1 < segments.count {
                index += 1
                currentSegmentIndex = index
            } else {
                finishChapter()
                return
            }
        }
    }

    /// WebSocket 流式 TTS：把当前句作为文本帧发送，累积二进制音频帧，收到 done 后播放。
    private func playWebSocketSegments(source: HttpTTS, generation gen: Int) async {
        var consecutiveFailures = 0
        while segments.indices.contains(index) {
            guard gen == generation, isActive else { return }
            await waitWhilePaused(generation: gen)
            guard gen == generation, isActive else { return }

            let segment = segments[index]
            updateSegmentState(segment)
            updateNowPlaying()
            do {
                let data = try await streamAudio(for: segment.text, source: source)
                try Task.checkCancellation()
                guard gen == generation else { return }
                let ext = Self.audioExtension(for: source.contentType)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tts-ws-\(UUID().uuidString).\(ext)")
                try data.write(to: url, options: .atomic)
                let completed = try await playAudioFile(url, generation: gen)
                try? FileManager.default.removeItem(at: url)
                guard completed, gen == generation else { return }
                consecutiveFailures = 0
                lastError = nil
            } catch is CancellationError {
                return
            } catch {
                if gen != generation || Task.isCancelled { return }
                consecutiveFailures += 1
                lastError = error.localizedDescription
                if consecutiveFailures >= 3 {
                    isSpeaking = false
                    isPaused = false
                    playbackTask = nil
                    updateNowPlaying(completed: true)
                    deactivateAudioSession()
                    return
                }
                let ok = await speakSystemAndWait(segment, generation: gen)
                guard ok, gen == generation else { return }
            }

            guard gen == generation else { return }
            if index + 1 < segments.count {
                index += 1
                currentSegmentIndex = index
            } else {
                finishChapter()
                return
            }
        }
    }

    private func streamAudio(for text: String, source: HttpTTS) async throws -> Data {
        guard let stream = makeWebSocketStream(for: source, send: text) else {
            throw TTSWebSocketStream.StreamError.invalidURL(source.url)
        }
        let collector = TTSWebSocketCollector()
        stream.onAudio = { collector.append($0) }
        stream.onState = { state in
            if state.lowercased() == "done" { collector.finish(.success(Data())) }
        }
        stream.onError = { message in
            collector.finish(.failure(TTSWebSocketStream.StreamError.server(message)))
        }
        stream.onClosed = { collector.closeIfNeeded() }
        try stream.connect()

        let timeout = DispatchWorkItem { collector.finish(.failure(TTSWebSocketCollector.CollectorError.timeout)) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        defer { timeout.cancel(); stream.close(reason: "tts segment finished") }
        return try await collector.wait()
    }

    private static func audioExtension(for contentType: String?) -> String {
        let value = (contentType ?? "").lowercased()
        if value.contains("wav") { return "wav" }
        if value.contains("m4a") || value.contains("mp4") { return "m4a" }
        if value.contains("aac") { return "aac" }
        if value.contains("ogg") { return "ogg" }
        return "mp3"
    }

    private func waitWhilePaused(generation gen: Int) async {
        while isPaused, gen == generation, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func playAudioFile(_ url: URL, generation gen: Int) async throws -> Bool {
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        guard player.play() else {
            throw TTSDriverError.audioDecodeFailed("播放器无法开始播放")
        }
        audioPlayer = player
        var pausedByController = false
        while true {
            if Task.isCancelled || gen != generation {
                player.stop()
                if audioPlayer === player { audioPlayer = nil }
                return false
            }
            if isPaused {
                if player.isPlaying {
                    player.pause()
                }
                pausedByController = true
            } else if pausedByController {
                player.play()
                pausedByController = false
            } else if !player.isPlaying {
                break
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        if audioPlayer === player { audioPlayer = nil }
        return true
    }

    private func effectiveHTTPRate(for segment: TTSSegment) -> Double {
        guard segment.role == .dialogue, multiRoleEnabled else { return Double(rate) }
        return min(max(Double(rate) * dialogueRateFactor, 0.1), 1.0)
    }

    // MARK: - 统一状态

    private func updateSegmentState(_ segment: TTSSegment) {
        currentSentence = segment.text
        currentSegmentIndex = index
        currentRole = segment.role
        currentRoleName = segment.characterName
        currentCharacterName = segment.characterName
        currentSegmentRange = segmentRanges.indices.contains(index) ? segmentRanges[index] : nil
        onProgress?(index, segmentCount)
    }

    private func seek(to target: Int) {
        guard !segments.isEmpty else { return }
        let destination = min(max(target, 0), segments.count - 1)
        stopInternal(clearSession: false)
        index = destination
        currentSegmentIndex = destination
        isSpeaking = true
        isPaused = false
        activateAudioSession()
        updateNowPlaying()
        if let source = selectedHTTPSource {
            currentSourceName = source.name
            startHTTPPlayback(source: source)
        } else {
            currentSourceName = "系统朗读"
            updateSegmentState(segments[index])
            speakSystem(segments[index])
        }
    }

    private func finishChapter() {
        systemWaitContinuation?.resume(returning: false)
        systemWaitContinuation = nil
        currentUtterance = nil
        audioPlayer = nil
        playbackTask = nil
        isSpeaking = false
        isPaused = false
        updateNowPlaying(completed: true)
        deactivateAudioSession()
        onChapterFinished?()
    }

    private func stopInternal(clearSession: Bool) {
        generation += 1
        playbackTask?.cancel()
        playbackTask = nil
        systemWaitContinuation?.resume(returning: false)
        systemWaitContinuation = nil
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
        isPaused = false
        lastError = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateAudioSession()

        if clearSession {
            segments = []
            segmentRanges = []
            currentSegmentRange = nil
            currentCharacterName = nil
            index = 0
            segmentCount = 0
            currentSegmentIndex = 0
            currentSentence = ""
            currentRole = .narrator
            currentRoleName = nil
            bookTitle = ""
            chapterTitle = ""
            currentSourceName = selectedHTTPSource?.name ?? "系统朗读"
        }
    }

    private func restartSystemSentenceForRateChangeIfNeeded() {
        guard isSpeaking, !isPaused, selectedHTTPSource == nil,
              systemWaitContinuation == nil,
              segments.indices.contains(index) else { return }
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        let segment = segments[index]
        updateSegmentState(segment)
        speakSystem(segment)
    }

    // MARK: - 音频会话 / 锁屏

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func updateNowPlaying(completed: Bool = false) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: bookTitle.isEmpty ? "指尖阅读" : bookTitle,
            MPMediaItemPropertyArtist: chapterTitle.isEmpty ? "朗读" : chapterTitle,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isSpeaking ? 1.0 : 0.0,
        ]
        if segmentCount > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentSegmentIndex
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = segmentCount
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = completed ? 1.0 : progress
            info[MPMediaItemPropertyPlaybackDuration] = 1.0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.stopCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.toggle() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.stop() }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipForward() }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipBackward() }
            return .success
        }
    }

    private func installInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == .began {
                    self.pause()
                } else if type == .ended {
                    let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                    if options.contains(.shouldResume) { self.resume() }
                }
            }
        }
    }

    // MARK: - 偏好

    private func persistPreferences() {
        runtime.preferences = TTSVoicePreferences(
            rate: Double(rate),
            multiRoleEnabled: multiRoleEnabled,
            narratorVoiceID: narratorVoiceID,
            dialogueVoiceID: dialogueVoiceID,
            dialogueRateFactor: dialogueRateFactor,
            selectedSourceID: selectedSourceID,
            characterVoices: characterVoices,
            recognizedCharacters: recognizedCharacters,
            autoCharacterVoices: autoCharacterVoices
        )
    }

    private func refreshSourceName() {
        currentSourceName = selectedHTTPSource?.name ?? "系统朗读"
    }

    // MARK: - 句 → 章节范围

    private static func ranges(for segments: [TTSSegment], in text: String) -> [NSRange] {
        let ns = text as NSString
        var cursor = 0
        return segments.map { segment in
            guard ns.length > 0 else { return NSRange(location: NSNotFound, length: 0) }
            let start = min(cursor, ns.length)
            let searchRange = NSRange(location: start, length: ns.length - start)
            var range = ns.range(of: segment.text, options: .literal, range: searchRange)
            if range.location == NSNotFound {
                range = ns.range(of: segment.text, options: .literal)
            }
            if range.location != NSNotFound {
                cursor = range.location + range.length
            }
            return range
        }
    }

    // MARK: - WebSocket 骨架

    /// 为某个 HTTP TTS 源建立 WebSocket 流（当前 UI 未接入，供后续流式朗读使用）。
    func makeWebSocketStream(for source: HttpTTS, send: String? = nil) -> TTSWebSocketStream? {
        let raw = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.lowercased().hasPrefix("ws://") || raw.lowercased().hasPrefix("wss://") else { return nil }
        return TTSWebSocketStream(configuration: TTSWebSocketConfiguration(
            url: raw,
            headers: HTTPTTSDriver.mergedHeaders(source: source, loginHeader: runtime.loginHeader(for: source.id)),
            send: send,
            contentType: source.contentType
        ))
    }
}

// MARK: - AVSpeechSynthesizerDelegate 桥

/// AVSpeechSynthesizerDelegate 是 ObjC 协议，用独立桥对象避免 @MainActor 隔离冲突。
private final class SpeechBridge: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: ((AVSpeechUtterance) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?(utterance)
    }
}
