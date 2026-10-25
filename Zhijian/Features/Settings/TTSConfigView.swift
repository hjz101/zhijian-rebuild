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
        ScrollView {
            VStack(spacing: 18) {
                systemSection
                characterSection
                httpSection
                cacheSection
                helpSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(QiBackground())
        .tint(ZJ.accent)
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
        QiSettingsSection(title: "系统朗读") {
            QiToggleRow(icon: "person.2.wave.2", title: "多角色（旁白 / 对话）", isOn: Binding(
                get: { tts.multiRoleEnabled },
                set: { tts.multiRoleEnabled = $0 }
            ))
            QiDivider()
            QiSliderRow(title: "语速", value: Binding(
                get: { Double(tts.rate) },
                set: { tts.setRate(Float($0)) }
            ), range: 0.3...0.9, step: 0.05) { String(format: "%.2f", $0) }
            QiDivider()
            voicePickerRow("旁白语音", icon: "text.bubble", autoLabel: "自动（推荐）", selection: Binding(
                get: { tts.narratorVoiceID ?? "" },
                set: { tts.narratorVoiceID = $0.isEmpty ? nil : $0 }
            ))
            QiDivider()
            voicePickerRow("对话语音", icon: "quote.bubble", autoLabel: "自动（不同于旁白）", selection: Binding(
                get: { tts.dialogueVoiceID ?? "" },
                set: { tts.dialogueVoiceID = $0.isEmpty ? nil : $0 }
            ))
            QiDivider()
            QiSliderRow(title: "对话语速", value: Binding(
                get: { tts.dialogueRateFactor },
                set: { tts.dialogueRateFactor = $0 }
            ), range: 0.7...1.3, step: 0.05) { String(format: "×%.2f", $0) }
            QiDivider()
            HStack(spacing: 10) {
                Button {
                    tts.play(text: sampleText, bookTitle: "试听", chapterTitle: "系统朗读")
                } label: {
                    Label("试听", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(ZJ.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    tts.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ZJ.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(ZJ.bgElev2, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!tts.isActive)
                .opacity(tts.isActive ? 1 : 0.5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            footer("系统语音来自 AVSpeechSynthesizer；增强/精品语音需在系统设置下载。多角色会把引号内内容标为对话，并可从「阿禾说/问道」等提示语中提取角色名。")
        }
    }

    private func voicePickerRow(_ title: String, icon: String, autoLabel: String, selection: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZJ.accent)
                .frame(width: 30, height: 30)
                .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
            Spacer()
            Picker("", selection: selection) {
                Text(autoLabel).tag("")
                ForEach(voices) { voice in
                    Text("\(voice.name) · \(voice.qualityLabel)").tag(voice.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(ZJ.accent)
            .font(.system(size: 12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: 智能角色

    private var characterSection: some View {
        QiSettingsSection(title: "角色音色（智能识别）") {
            QiToggleRow(icon: "person.crop.circle.badge.questionmark", title: "自动分配角色音色", isOn: Binding(
                get: { tts.autoCharacterVoices },
                set: { tts.autoCharacterVoices = $0 }
            ))
            QiDivider()
            if tts.recognizedCharacters.isEmpty {
                Text("朗读一章后自动识别角色，并按角色分配不同语音")
                    .font(.system(size: 12))
                    .foregroundStyle(ZJ.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                ForEach(tts.recognizedCharacters, id: \.self) { name in
                    HStack(spacing: 12) {
                        Text(name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ZJ.textPrimary)
                        Spacer()
                        Picker("", selection: Binding(
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
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(ZJ.accent)
                        .font(.system(size: 12))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            footer("本地启发式识别：引号归属（“…… ”阿禾说 / 阿禾：“……”）与「说道/问道/笑道」等提示语；每个角色自动分配不同中文语音，可逐角色覆盖。")
        }
    }

    // MARK: HTTP TTS 源

    private var httpSection: some View {
        QiSettingsSection(title: "HTTP TTS 源") {
            if sources.sources.isEmpty {
                Text("尚未导入 HTTP TTS 源")
                    .font(.system(size: 13))
                    .foregroundStyle(ZJ.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }

            ForEach(sources.sources) { source in
                sourceRow(source)
                    .contextMenu {
                        Button { editingSource = source } label: { Label("编辑", systemImage: "pencil") }
                        Button(role: .destructive) {
                            sources.remove(source)
                            refreshCacheStats()
                        } label: { Label("删除", systemImage: "trash") }
                    }
                QiDivider()
            }

            actionRow("新增 HTTP TTS 源", icon: "plus.circle") {
                editingSource = sources.makeBlank()
            }
            QiDivider()
            actionRow("导入 JSON 文件", icon: "doc.badge.plus") { showFileImporter = true }
            QiDivider()
            actionRow("粘贴 JSON 导入", icon: "doc.on.clipboard") { showPasteImport = true }
            QiDivider()
            actionRow("导出 JSON", icon: "square.and.arrow.up", disabled: sources.sources.isEmpty) { exportSources() }
            footer("URL 三种写法：① 模板 `{{speakText}}` / `{{speakSpeed}}`；② `URL,{JSON}` POST（body 支持模板）；③ `@js:` 独立 JavaScriptCore 脚本。header 支持 JSON 对象或每行 `Key: Value`。")
        }
    }

    private func actionRow(_ title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ZJ.accent)
                    .frame(width: 30, height: 30)
                    .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ZJ.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(ZJ.textTertiary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ZJ.textPrimary)
                Text(source.url.isEmpty ? "未配置 URL" : source.url)
                    .font(.system(size: 10.5))
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
                ProgressView().controlSize(.small)
            } else {
                Button {
                    test(source)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(ZJ.accent)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: 缓存 / 说明

    private var cacheSection: some View {
        QiSettingsSection(title: "缓存") {
            QiRow(icon: "waveform.path.ecg", title: "音频缓存",
                  subtitle: "Caches/ZhijianTTS",
                  value: "\(cacheCount) 段 · \(formattedBytes(cacheBytes))")
            QiDivider()
            actionRow("清理 TTS 音频缓存", icon: "trash", disabled: cacheCount == 0) {
                HTTPTTSDriver.shared.clearCache()
                refreshCacheStats()
            }
            footer("缓存按「源 id + 文本 + 语速」去重；清理不会影响 TTS 源配置。")
        }
    }

    private var helpSection: some View {
        QiSettingsSection(title: "说明与缺口") {
            VStack(alignment: .leading, spacing: 8) {
                Text("· Header / 登录 Header 会注入每次 HTTP TTS 请求；勾选 enabledCookieJar 时还会带 HTTPCookieStorage 中的 Cookie。")
                Text("· `loginUrl/loginUi/loginCheckJs` 字段已保留，但内置浏览器登录流程尚未接入；登录 Header 可先在编辑页手动填写。")
                Text("· WebSocket 流式朗读已有 URLSessionWebSocketTask 骨架（TTSWebSocketStream），尚未接入播放器与 UI。")
                Text("· HTTP 音频用 AVAudioPlayer 解码 mp3 / wav / m4a / aac；连续 3 句失败会停止，单句失败用系统语音兜底。")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(ZJ.textTertiary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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

                TextField("loginUrl", text: stringBinding(\.loginUrl))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if let loginUrl = draft.loginUrl, !loginUrl.isEmpty {
                    Button {
                        showLogin = true
                    } label: {
                        Label("打开登录页并提取 Cookie", systemImage: "globe")
                    }
                }
                TextField("loginUi（保留字段）", text: stringBinding(\.loginUi))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("请求 / 登录")
            } footer: {
                Text("登录 Header 会与 header 合并注入 HTTP TTS 请求，仅保存在本机 Application Support/tts_runtime.json；loginUrl 可打开内置登录页抓取 Cookie，loginUi 仍未接入。")
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
        .sheet(isPresented: $showLogin) {
            if let url = draft.loginUrl, !url.isEmpty {
                TTSLoginSheet(urlString: url, sourceName: draft.name) { header in
                    loginHeader = header
                }
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
