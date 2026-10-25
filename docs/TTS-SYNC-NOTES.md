# TTS / 同步分线说明（TTS-SYNC-NOTES）

> 分线：`tts-sync` · 写入范围：`Core/TTS/**`、`Core/Sync/**`、`Features/TTS/**`、
> `Features/Settings/TTSConfigView.swift`、`Features/Settings/BackupView.swift`、本文件。
> 未修改 `AppEnvironment`、Models、Reader、SettingsView。

## 1. 文件清单

### Core/TTS
| 文件 | 内容 |
|---|---|
| `TTSSentenceSplitter.swift` | 中英文句子切分（标点/换行，单句上限 300 字）；引号/「说·道·问·答」旁白/对话切分与角色名猜测 |
| `TTSVoiceCatalog.swift` | 中文系统语音目录；`TTSVoicePreferences`；`TTSRuntimeStore`（登录 Header / 源变量 / 偏好 JSON） |
| `TTSController.swift` | 统一朗读控制器：系统 AVSpeechSynthesizer + HTTP TTS + 多角色 + 暂停/继续/停止 + 章节结束回调 + Now Playing/远程控制 |
| `TTSSourceStore.swift` | `HttpTTS` 列表 JSON 持久化、Legado 兼容导入、导出文件 |
| `HTTPTTSDriver.swift` | 三种 URL 模式、Header/loginHeader/Cookie 注入、contentType 校验、Caches 音频缓存、AVAudioPlayer 解码 |
| `TTSWebSocketStream.swift` | URLSessionWebSocketTask 流式音频骨架（尚未接播放器/UI） |

### Core/Sync
| 文件 | 内容 |
|---|---|
| `ZipArchive.swift` | 复用旧工程 `ZipWriter`/`ZipReader`（store 写入、stored/deflate 读取） |
| `BackupModels.swift` | `BackupDestination`、`BackupError`、`BackupRestoreSummary`、`RemoteBackupItem` |
| `BackupService.swift` | `.zjbk` 导出/恢复；WebDAV 上传/下载/列表/删除 |
| `WebDAVClient.swift` | PROPFIND / MKCOL / PUT / GET / DELETE；Basic Auth；XML 解析；错误映射 |
| `WebDAVConfigStore.swift` | `WebDAVConfig` JSON 持久化（Application Support/Zhijian/webdav.json） |

### UI
| 文件 | 内容 |
|---|---|
| `Features/TTS/TTSPlayerBar.swift` | 迷你朗读条：来源、角色、进度、上一句/播放暂停/下一句/停止、语速 |
| `Features/Settings/TTSConfigView.swift` | 系统语音/多角色/语速、HTTP 源列表/新增/编辑/测试/删除/导入/导出、缓存清理 |
| `Features/Settings/BackupView.swift` | 本地导出/恢复、WebDAV 配置/上传/下载/删除/测试、最近时间 |

## 2. 已可用功能

### TTS
- **系统朗读**：AVSpeechSynthesizer；播放/暂停/继续/停止；0.2–1.0 语速；自动选择中文增强/精品语音。
- **句子队列**：中文 `。！？；…`、英文 `.?!;`、换行切分；引号跟随前句；超长句在逗号/空白处硬切到 300 字。
- **多角色 MVP**：成对引号内容 → `.dialogue`，其余 → `.narrator`；支持「说道/问道/答道…：」冒号对话；从「阿禾说」等提示语提取 1–4 字角色名。旁白/对话可配不同系统语音，对话语速有 0.7–1.3 倍率；`TTSController.currentRole` / `currentRoleName` 对外暴露。
- **章节回调**：自然读完后 `onChapterFinished`；每句 `onProgress(index, count)`。
- **锁屏**：`MPNowPlayingInfoCenter` 元数据 + 播放/暂停/上下句/停止远程命令；处理音频中断。
- **HTTP TTS**：
  - 模板 `{{speakText}}` / `{{speakSpeed}}`（speed = `Int(rate*10)`，1–30，URL 编码）。
  - `URL,{JSON}`：`method`/`body`/`headers`；body 内模板按 JSON 转义（支持 `{\"text\":\"{{speakText}}\"}`）。
  - `@js:`：独立 JSContext，可读写 `speakText`/`speakSpeed`/`source`，`java.ajax/get/post`（同步 HTTPClient）、`base64Encode/Decode`、`md5Encode`、`getWebViewUA`；返回 URL、`{url,method,body,headers}` 或 base64/`data:audio` 音频。
  - Header 支持 JSON 对象或每行 `Key: Value`/`Key=Value`；`loginHeader` 由 `TTSRuntimeStore` 手动维护并覆盖合并；`enabledCookieJar` 时注入 HTTPCookieStorage Cookie。
  - contentType：声明值支持 `audio/*`、`a|b`、正则或包含匹配；未声明时拒绝 `text/html`/`application/json`/明显 HTML/JSON 响应。
  - 音频缓存：`Caches/ZhijianTTS/<sha256(source.id,url,text,speed)>.<ext>`；命中不请求；AVAudioPlayer 校验 mp3/wav/m4a/aac；配置页可清缓存。
  - 失败策略：单句失败用系统语音兜底；连续 3 句失败停止并显示 `lastError`。
  - 并发/限速：`concurrentRate` 支持 `"1500"`（1.5s）与 `"1/1000"`（1/s），默认 0.25s。
- **WebSocket 骨架**：连接、发送、文本/二进制接收、`{"type":"audio|send|state|done|error"}` 解析、最大字节限制（未接入 UI/播放器）。

### 备份 / 同步
- **`.zjbk`** = 标准 ZIP（store）：
  - 根 `manifest.json`（`BackupManifest`，version=1、appVersion、createdAt、deviceName、counts、includesLocalBooks=false、categories）
  - `bookshelf.json` / `sources.json` / `settings.json` / `tts_sources.json`
  - 不包含本地书正文文件、QiReader 资源、Cookie、AI Key；不加密。
- **本地**：`export() throws -> URL`（临时目录）、`restore(url:) async throws`（后台解码 + 主线程整体替换）；最近时间/恢复统计持久化。
- **WebDAV**：`WebDAVClient` 完成 PROPFIND（Depth 0/1、XML 解析 href/collection/getcontentlength/getlastmodified）、MKCOL 多级目录、PUT、GET、DELETE；Basic Auth；401/403/404/405/409/423/507/5xx 映射为中文错误。
- **WebDAV 配置**：`WebDAVConfigStore` 存 Application Support/Zhijian/webdav.json；支持多配置、当前配置、增删改。密码**明文**，UI 已显示警告。
- **远程备份**：上传当前备份、列出 `.zjbk`、按名字下载、下载最新、删除、立即恢复。
- **已验证**（模拟器 / 本地 mock 服务）：
  - 备份导出 → 恢复 round-trip：`bookshelf/sources/settings/tts_sources` 全部恢复，manifest 可读。
  - HTTP TTS 模板 / `,{JSON}` POST / `@js:` 三种模式均成功；二次请求命中缓存；HTML 响应被 contentType 校验拒绝；HTTP 源实际播放成功。
  - mock WebDAV：checkConnection、MKCOL、PUT、PROPFIND 列表、GET 下载、Basic Auth 头均成功。
  - `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17'` **BUILD SUCCEEDED**。

## 3. Lead 需要接入的入口（不在本分线写入范围）

### 3.1 设置页入口（SettingsView）

```swift
Section("朗读与数据") {
    NavigationLink("朗读与 TTS") { TTSConfigView() }
    NavigationLink("备份与同步") { BackupView() }
}
```

`SettingsView` 已在 `NavigationStack` 内且环境注入了 `AppEnvironment`，上述 destination 会自动继承；若改用 sheet 展示，需要显式 `.environmentObject(env)`。

### 3.2 阅读页迷你条

推荐直接传 controller（不要用环境包装，避免观察不到嵌套对象变化）：

```swift
ReaderScreen(book: book)
    .safeAreaInset(edge: .bottom) {
        TTSPlayerBar(tts: env.tts)
    }
```

或全局挂在 RootView 的 TabView 上。`TTSPlayerBarEnvironment()` 也可用，但需要 `env` 环境对象。

### 3.3 阅读器 TTS 调用建议

当前 `ReaderViewModel.toggleTTS()` 只用了协议里的 `speak(text)` / `stop()`。为了让迷你条显示书名/章节、暂停后能继续、章节读完自动接下一章，建议 Reader 分线：

```swift
// 开始（替代 await tts.speak(text)）
env.tts.play(text: currentPageText,
             bookTitle: model.book.title,
             chapterTitle: model.chapterTitle)

// 暂停按钮：判断 isPaused
if env.tts.isPaused { env.tts.resume() } else if env.tts.isSpeaking { env.tts.pause() }

// 章节读完（在 Reader 初始化时设置一次）
env.tts.onChapterFinished = { [weak model] in
    guard let model else { return }
    Task {
        await model.nextChapter()
        env.tts.play(text: model.currentPageText,
                     bookTitle: model.book.title,
                     chapterTitle: model.chapterTitle)
    }
}
```

`TTSController` 还提供 `skipForward()` / `skipBackward()` / `seek` 内部能力；`rate` 可绑定 `settings.ttsRate`（`env.tts.setRate(Float(env.settings.settings.ttsRate))`）。

### 3.4 Info.plist（Lead 决定）

- 锁屏/后台持续朗读需要 `UIBackgroundModes` 增加 `audio`。当前只在 App 前台/系统允许范围内工作；Now Playing 元数据与远程控制已实现。
- 希望「文件」App 直接识别/打开 `.zjbk` 时，可增加 `UTImportedTypeDeclarations`（`com.zhijian.backup`，conforms to `public.zip-archive`）与 `CFBundleDocumentTypes`。当前 `fileImporter` 同时接受 `.zjbk` 动态类型、`.zip`、`.data`，已可手动选择。

## 4. 已知缺口 / 后续

1. **HTTP TTS 登录**：`loginUrl/loginUi/loginCheckJs` 字段保留，但内置浏览器登录流程未实现；目前只能在 TTS 源编辑页手填「登录 Header」，或依赖已有 Cookie。
2. **WebSocket**：`TTSWebSocketStream` 只有连接/收发骨架，未接入 `HTTPTTSDriver` 的流式缓存与播放；需要源编写约定（`java.webSocket`）后再接。
3. **HTTP 播放策略**：逐句串行下载播放，无预取/并发；首句 30s 超时；连续 3 句失败停止；没有“下载 A 句时预取 A+1”与尾音裁剪。
4. **音频格式**：用 AVAudioPlayer 校验/播放，任务要求 mp3/wav/m4a/aac 已覆盖；ogg/flac 是否可放取决于系统解码器，校验失败会报错。
5. **多角色**：系统语音按旁白/对话两个角色映射；HTTP 源只调整 `speakSpeed` 倍率，不能按角色切换不同 HTTP 源/音色；角色名提取是规则启发式，非 AI。
6. **备份**：无加密/密码、无 iCloud、无自动备份、无增量/冲突合并；不含本地书正文、Cookie、AI Key；恢复是整体替换。WebDAV 密码明文存 Application Support，建议后续迁 Keychain。
7. **恢复联动**：恢复 `settings.json` 后不会自动更新正在运行的 `TTSController.rate`/`selectedSourceID`；Lead 可在设置页绑定或恢复完成后重新读取。
8. **UTType**：`.zjbk` 尚未在 Info.plist 注册；`manifest.includesLocalBooks=false`，本地书跨设备恢复只有元数据。
9. **阅读器接入**：迷你条尚未挂到阅读页/全局；Reader 目前只读当前页文本，书名/章节标题/暂停恢复/自动下一章需要按 §3.3 接线。
10. **Swift 6 并发警告**：`TTSControlling` 协议（ReaderContracts）未标注 `@MainActor`，`TTSController` 的实现会产生一条 Swift 6 模式警告（当前 Swift 5 可正常编译）；建议 Reader 分线将协议标为 `@MainActor`。

## 5. 验证命令

```bash
xcodebuild -project Zhijian.xcodeproj -scheme Zhijian \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/zj-tts build
```

最近一次结果：`** BUILD SUCCEEDED **`。
