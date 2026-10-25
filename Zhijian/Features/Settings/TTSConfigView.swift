// TTSConfigView.swift — 系统朗读 / 多角色 / HTTP TTS 源管理
//
// 入口由 Lead 在 SettingsView 中加入，例如：
// NavigationLink("朗读与 TTS") { TTSConfigView() }
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct TTSConfigView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TTSConfigContent(tts: env.tts)
    }
}

private struct TTSConfigContent: View {
    @ObservedObject var tts: TTSController
    @ObservedObject private var sources: TTSSourceStore

    @State private var voices: [TTSVoiceOption] = []
    @State private var editingSource: HttpTTS?
    @State private var showPasteImport = false
    @State private var showFileImporter = false
    @State private var importText = ""
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var previewPlayer: AVAudioPlayer?
    @State private var testingSourceID: String?
    @State private var cacheCount = 0
    @State private var cacheBytes: Int64 = 0

    private let sampleText = "山间的雾还没有散。阿禾说：“今年的桂花开得早。”我点点头，没有说话。"

    init(tts: TTSController) {
        self.tts = tts
        _sources = ObservedObject(wrappedValue: tts.ttsSources)
    }

    var body: some View {
        Form {
            systemSection
            characterSection
            httpSection
            cacheSection
            helpSection
        }
        .navigationTitle("朗读 / TTS")
        .onAppear {
            if voices.isEmpty { voices = TTSVoiceCatalog.chineseVoices() }
            refreshCacheStats()
            if ProcessInfo.processInfo.arguments.contains("-ttsCharacterTest") {
                tts.play(text: "阿禾说：“今年的桂花开得早。”老陈笑道：“那就再去看看。”",
                         bookTitle: "角色识别测试", chapterTitle: "第一章")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { tts.stop() }
            }
        }
        .sheet(item: $editingSource) { source in
            NavigationStack {
                TTSourceEditorView(
                    source: source,
                    loginHeader: TTSRuntimeStore.shared.loginHeader(for: source.id)
                ) { updated, loginHeader in
                    sources.update(updated)
                    TTSRuntimeStore.shared.setLoginHeader(loginHeader, for: updated.id)
                    editingSource = nil
                } onCancel: {
                    editingSource = nil
                }
            }
        }
        .sheet(isPresented: $showPasteImport) {
            pasteImportSheet
        }
        .sheet(isPresented: $showShareSheet) {
            exportSheet
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let count = try sources.importJSONFile(url)
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        presentAlert("导入成功", "新增/覆盖 \(count) 个 TTS 源")
                    }
                } catch {
                    presentAlert("导入失败", error.localizedDescription)
                }
            case .failure(let error):
                presentAlert("导入失败", error.localizedDescription)
            }
        }
        .alert(alertTitle.isEmpty ? "提示" : alertTitle, isPresented: $showAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: 系统朗读

    private var systemSection: some View {
        Section {
            Toggle("多角色（旁白 / 对话）", isOn: Binding(
                get: { tts.multiRoleEnabled },
                set: { tts.multiRoleEnabled = $0 }
            ))

            HStack(spacing: ZJ.s3) {
                Text("语速")
                Slider(value: Binding(
                    get: { Double(tts.rate) },
                    set: { tts.setRate(Float($0)) }
                ), in: 0.3...0.9, step: 0.05)
                Text(String(format: "%.2f", tts.rate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            Picker("旁白语音", selection: Binding(
                get: { tts.narratorVoiceID ?? "" },
                set: { tts.narratorVoiceID = $0.isEmpty ? nil : $0 }
            )) {
                Text("自动（推荐）").tag("")
                ForEach(voices) { voice in
                    Text("\(voice.name) · \(voice.qualityLabel)").tag(voice.id)
                }
            }

            Picker("对话语音", selection: Binding(
                get: { tts.dialogueVoiceID ?? "" },
                set: { tts.dialogueVoiceID = $0.isEmpty ? nil : $0 }
            )) {
                Text("自动（不同于旁白）").tag("")
                ForEach(voices) { voice in
                    Text("\(voice.name) · \(voice.qualityLabel)").tag(voice.id)
                }
            }

            HStack(spacing: ZJ.s3) {
                Text("对话语速")
                Slider(value: Binding(
                    get: { tts.dialogueRateFactor },
                    set: { tts.dialogueRateFactor = $0 }
                ), in: 0.7...1.3, step: 0.05)
                Text(String(format: "×%.2f", tts.dialogueRateFactor))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            HStack(spacing: ZJ.s3) {
                Button {
                    tts.play(text: sampleText, bookTitle: "试听", chapterTitle: "系统朗读")
                } label: {
                    Label("试听", systemImage: "play.circle")
                }
                Button {
                    tts.stop()
                } label: {
                    Label("停止试听", systemImage: "stop.circle")
                }
                .disabled(!tts.isActive)
            }
        } header: {
            Text("系统朗读")
        } footer: {
            Text("系统语音来自 AVSpeechSynthesizer；增强/精品语音需在系统设置下载。多角色会把引号内内容标为对话，并可从「阿禾说/问道」等提示语中提取角色名。")
        }
    }

    // MARK: 智能角色

    private var characterSection: some View {
        Section {
            Toggle("自动分配角色音色", isOn: Binding(
                get: { tts.autoCharacterVoices },
                set: { tts.autoCharacterVoices = $0 }
            ))
            if tts.recognizedCharacters.isEmpty {
                Text("朗读一章后自动识别角色，并按角色分配不同语音")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tts.recognizedCharacters, id: \.self) { name in
                    Picker(name, selection: Binding(
                        get: { tts.characterVoices[name] ?? "" },
                        set: { newValue in
                            if newValue.isEmpty {
                                tts.characterVoices.removeValue(forKey: name)
                            } else {
                                tts.characterVoices[name] = newValue
                            }
                        }
                    )) {
                        Text("自动").tag("")
                        ForEach(voices) { voice in
                            Text("\(voice.name) · \(voice.qualityLabel)").tag(voice.id)
                        }
                    }
                }
            }
        } header: {
            Text("角色音色（智能识别）")
        } footer: {
            Text("本地启发式识别：引号归属（“……”阿禾说 / 阿禾：“……”）与「说道/问道/笑道」等提示语；每个角色自动分配不同中文语音，可逐角色覆盖。")
        }
    }

    // MARK: HTTP TTS 源

    private var httpSection: some View {
        Section {
            if sources.sources.isEmpty {
                Text("尚未导入 HTTP TTS 源")
                    .foregroundStyle(.secondary)
            }

            ForEach(sources.sources) { source in
                sourceRow(source)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            sources.remove(source)
                            refreshCacheStats()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            editingSource = source
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(ZJ.celadon)
                    }
            }

            Button {
                editingSource = sources.makeBlank()
            } label: {
                Label("新增 HTTP TTS 源", systemImage: "plus.circle")
            }

            Button {
                showFileImporter = true
            } label: {
                Label("导入 JSON 文件", systemImage: "doc.badge.plus")
            }

            Button {
                showPasteImport = true
            } label: {
                Label("粘贴 JSON 导入", systemImage: "doc.on.clipboard")
            }

            Button {
                exportSources()
            } label: {
                Label("导出 JSON", systemImage: "square.and.arrow.up")
            }
            .disabled(sources.sources.isEmpty)
        } header: {
            Text("HTTP TTS 源")
        } footer: {
            Text("URL 三种写法：① 模板 `{{speakText}}` / `{{speakSpeed}}`；② `URL,{JSON}` POST（body 支持模板）；③ `@js:` 独立 JavaScriptCore 脚本，返回 URL、请求对象或 base64 音频。header 支持 JSON 对象或每行 `Key: Value`。")
        }
    }

    private func sourceRow(_ source: HttpTTS) -> some View {
        HStack(spacing: ZJ.s3) {
            Button {
                sources.toggle(source)
            } label: {
                Image(systemName: (source.enabled ?? true) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle((source.enabled ?? true) ? ZJ.celadon : ZJ.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel((source.enabled ?? true) ? "停用" : "启用")

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .foregroundStyle(ZJ.textPrimary)
                Text(source.url.isEmpty ? "未配置 URL" : source.url)
                    .font(.caption2)
                    .foregroundStyle(ZJ.textTertiary)
                    .lineLimit(1)
                if let contentType = source.contentType, !contentType.isEmpty {
                    Text(contentType)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ZJ.textTertiary)
                }
            }

            Spacer(minLength: 4)

            if testingSourceID == source.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    test(source)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(source.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("测试 \(source.name)")
            }

            Button {
                editingSource = source
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(ZJ.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑 \(source.name)")
        }
        .contentShape(Rectangle())
    }

    // MARK: 缓存 / 说明

    private var cacheSection: some View {
        Section {
            HStack {
                Text("音频缓存")
                Spacer()
                Text("\(cacheCount) 段 · \(formattedBytes(cacheBytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                HTTPTTSDriver.shared.clearCache()
                refreshCacheStats()
            } label: {
                Label("清理 TTS 音频缓存", systemImage: "trash")
            }
            .disabled(cacheCount == 0)
        } header: {
            Text("缓存")
        } footer: {
            Text("缓存位于 Caches/ZhijianTTS，按「源 id + 文本 + 语速」去重；清理不会影响 TTS 源配置。")
        }
    }

    private var helpSection: some View {
        Section("说明与缺口") {
            Text("· Header / 登录 Header 会注入每次 HTTP TTS 请求；勾选 enabledCookieJar 时还会带 HTTPCookieStorage 中的 Cookie。")
                .font(.footnote)
            Text("· `loginUrl/loginUi/loginCheckJs` 字段已保留，但内置浏览器登录流程尚未接入；登录 Header 可先在编辑页手动填写。")
                .font(.footnote)
            Text("· WebSocket 流式朗读已有 URLSessionWebSocketTask 骨架（TTSWebSocketStream），尚未接入播放器与 UI。")
                .font(.footnote)
            Text("· HTTP 音频用 AVAudioPlayer 解码 mp3 / wav / m4a / aac；连续 3 句失败会停止，单句失败用系统语音兜底。")
                .font(.footnote)
        }
    }

    // MARK: 操作

    @MainActor
    private func test(_ source: HttpTTS) {
        guard testingSourceID == nil else { return }
        testingSourceID = source.id
        Task {
            defer { testingSourceID = nil }
            do {
                let url = try await HTTPTTSDriver.shared.previewFile(text: sampleText, source: source)
                let player = try AVAudioPlayer(contentsOf: url)
                previewPlayer?.stop()
                previewPlayer = player
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .spokenAudio)
                try? session.setActive(true)
                player.play()
            } catch {
                presentAlert("测试失败", error.localizedDescription)
            }
        }
    }

    private func exportSources() {
        do {
            exportURL = try sources.exportFile()
            showShareSheet = true
        } catch {
            presentAlert("导出失败", error.localizedDescription)
        }
    }

    private func importPasted() {
        do {
            let count = try sources.importJSON(importText)
            showPasteImport = false
            importText = ""
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                presentAlert("导入成功", "新增/覆盖 \(count) 个 TTS 源")
            }
        } catch {
            presentAlert("导入失败", error.localizedDescription)
        }
    }

    private func refreshCacheStats() {
        let stats = HTTPTTSDriver.shared.cacheStats()
        cacheCount = stats.count
        cacheBytes = stats.bytes
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func presentAlert(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    // MARK: 子 Sheet

    private var pasteImportSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ZJ.s3) {
                Text("粘贴 Legado / 栖阅的 tts_sources.json；支持顶层数组或 {\"sources\":[...]}。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $importText)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: ZJ.rSm)
                            .strokeBorder(ZJ.separator, lineWidth: 1)
                    )
            }
            .padding()
            .navigationTitle("粘贴导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showPasteImport = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { importPasted() }
                        .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var exportSheet: some View {
        NavigationStack {
            VStack(spacing: ZJ.s5) {
                Image(systemName: "waveform.and.doc")
                    .font(.system(size: 44))
                    .foregroundStyle(ZJ.accent)
                Text("TTS 源已导出")
                    .font(.headline)
                Text("\(sources.sources.count) 个源 · JSON")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("分享 / 存储 JSON", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ZJ.accent)
                }
                Button("完成") { showShareSheet = false }
                    .foregroundStyle(.secondary)
            }
            .padding(ZJ.s6)
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 源编辑页

private struct TTSourceEditorView: View {
    @State private var draft: HttpTTS
    @State private var loginHeader: String
    @State private var showLogin = false
    private let onSave: (HttpTTS, String) -> Void
    private let onCancel: () -> Void

    init(
        source: HttpTTS,
        loginHeader: String,
        onSave: @escaping (HttpTTS, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: source)
        _loginHeader = State(initialValue: loginHeader)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $draft.name)
                TextField("URL / 模板 / @js:", text: $draft.url, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(2...6)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("基本信息")
            } footer: {
                Text("示例：`https://tts.example.com/speak?text={{speakText}}&speed={{speakSpeed}}` 或 `@js:` 脚本。")
            }

            Section {
                TextField("contentType（如 audio/mpeg 或 audio/）", text: stringBinding(\.contentType))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("concurrentRate（如 1/1000 或 1500）", text: stringBinding(\.concurrentRate))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                VStack(alignment: .leading, spacing: 4) {
                    Text("header（JSON 或每行 Key: Value）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: stringBinding(\.header))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 76)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("登录 Header（本地保存）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $loginHeader)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 64)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                TextField("loginUrl（保留字段，登录流程未接入）", text: stringBinding(\.loginUrl))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("loginUi（保留字段）", text: stringBinding(\.loginUi))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("请求 / 登录")
            } footer: {
                Text("登录 Header 会与 header 合并注入 HTTP TTS 请求，仅保存在本机 Application Support/tts_runtime.json。")
            }

            Section {
                Toggle("启用", isOn: Binding(
                    get: { draft.enabled ?? true },
                    set: { draft.enabled = $0 }
                ))
                Toggle("启用 Cookie Jar", isOn: Binding(
                    get: { draft.enabledCookieJar ?? false },
                    set: { draft.enabledCookieJar = $0 }
                ))
            } header: {
                Text("状态")
            }
        }
        .navigationTitle(draft.name.isEmpty ? "编辑 TTS 源" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(draft, loginHeader)
                }
                .disabled(draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func stringBinding(_ keyPath: WritableKeyPath<HttpTTS, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}
