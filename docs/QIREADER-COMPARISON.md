# 指尖阅读 2.1 vs 栖阅（QiReader）详细对比

> 对照依据：[栖阅逆向分析报告](file:///Users/a706/Documents/deepseek-harness/default-workspace/qireader/report/栖阅-QiReader-逆向分析报告.md)（360 个源文件、25,294 个函数名、364 个 ObjC 类）与本仓库当前代码/文档（81 个 Swift 文件、约 2.5 万行）。
> 图例：✅ 对齐或更好 · 🟡 部分实现/语义有差异 · ❌ 缺失。

## 0. 一句话结论

- **骨架已对齐**：Legado 书源模型与规则、native TextKit 分页、WKWebView 富文本、系统/HTTP/WS TTS、备份/WebDAV、段评/章末评论、TXT/EPUB/PDF/漫画。
- **最大差距不在“能不能读”**，而在 **内容生态与高级排版**：发现页、书源编辑/分组/导出、替换规则/章节规则、双页/翻页动画/音量键、HTML 章节标题设计器、阅读统计、自定义主题/字体/背景、AI 角色、iCloud 文档镜像、URL Scheme 与主题包导入。
- **反向优势**：备份 AES-GCM 加密、fastjson/Gson 存根、RAR/7z 通过 libarchive、JSC 执行超时、四种阅读器统一 TTS 句级高亮、评论冲突墓碑同步、无远程后端/无硬编码密钥。

## 1. 总体规模与架构

| 维度 | 栖阅 QiReader | 指尖阅读 2.1 | 差距 |
|---|---|---|---|
| 代码规模 | 360 Swift 文件 / 25,294 函数名 / 178 应用类 | 81 Swift 文件 / ~2.5 万行 | 🟡 约为其 1/4 文件量 |
| 最低系统 | iOS 17 | iOS 17 | ✅ |
| UI | SwiftUI + UIKit | SwiftUI + UIKit | ✅ |
| 分页内核 | native TextKit | native TextKit | ✅ |
| 滚动内核 | WKWebView + reader.js（7 章窗口） | UITextView 整章滚动 | 🟡 无虚拟窗口/锚点补偿 |
| 第三方依赖 | SwiftSoup/Kanna/SwiftyJSON/ZIPFoundation/Unrar/SevenZip/Sextant 等 | 无 SPM 依赖（系统框架 + 自研） | 🟡 功能广度换依赖轻量 |
| 二进制体积 | 28.4 MB | 11.5 MB（未签名 IPA） | ✅ 更小 |
| 远程后端 | 有（25+ accessToken 端点 + WebSocket） | 无 | 🟡 功能少但攻击面小 |

## 2. 书源引擎（Legado 兼容）

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| BookSource 35 字段 | ✅ | ✅ | 对齐 |
| 规则链 / `{{}}` / `@put` / `@get` / 索引 / `##` | ✅ | ✅ | 对齐 |
| CSS / XPath / JSONPath / 正则 / JS / WebJs | ✅ | ✅ | 对齐 |
| `java.*` 网络/编码/加密/压缩/文件 | ✅ 绝大多数 | ✅ 大部分 | 🟡 少量边界 API 未覆盖 |
| jsoup / JXDocument | ✅ | ✅ | 对齐 |
| fastjson / Gson | ❌ 无存根 | ✅ 已实现 JSON/JSONObject/JSONArray、Gson/JsonParser | ✅ 我们更好 |
| ZIP 读取/解包 | ✅ | ✅ | 对齐 |
| RAR / 7z 读取 | ✅ 原生库 | ✅ libarchive 弱链接（7z 实测，RAR 未构造样本） | 🟡 待 RAR 回归 |
| `@webjs` / `ruleContent.webJs` | ✅ | ✅ | 对齐 |
| `sourceRegex` / XHR-fetch 拦截 | ✅ BackstageWebView 完整拦截 | ✅ 离屏 WebView 注入拦截；约 2.5s 窗口、不改请求头 | 🟡 窗口/请求改写不足 |
| `loginCheckJs` | ✅ | ✅ 每次响应后执行 | 对齐 |
| `loginUrl` + `loginUi` 原生登录 | ✅ LoginService 38 方法、6 种 UI 控件 | ❌ 书源侧未接；仅 TTS 登录页 | ❌ 明显缺口 |
| Cookie 持久化 | ✅ PSL eTLD+1 + CookieBridge + WebView Cookie | ✅ `cookies.json` 域级持久化 + 跨管线共享 | 🟡 无 PSL、无 WebView 同步 |
| 登录态 `loginInfo` 持久化 | ✅ 按源保存 | 🟡 仅进程内 JS 变量 | ❌ 重启丢失 |
| 发现/Explore | ✅ 分类/筛选/信息流/网格 | ❌ 无 | ❌ 大缺口 |
| 搜索多源并发 | ✅ | ✅ | 对齐 |
| 搜索分页/取消/结果缓存 | ✅ | ❌ 单页、无取消、无缓存 | ❌ 缺口 |
| 替换规则（13 字段） | ✅ | ❌ | ❌ 缺口 |
| 章节规则（目录/正文/广告清理） | ✅ | ❌ | ❌ 缺口 |
| 书源分组/编辑/导出 | ✅ | 🟡 导入/启停/删除；无编辑/导出/分组 | ❌ 管理能力弱 |
| 书源全流程/批量测试 | ✅ | ✅ 四阶段体检 + 批量测试 + 诊断 | ✅ 对齐/更直观 |
| `jsLib` 共享脚本 | ✅ SharedJsScope | ❌ 字段保留未执行 | ❌ 缺口 |
| DNS 覆盖 / 代理（http/socks） | ✅ 本地 CONNECT 隧道 | ❌ | ❌ 缺口 |
| 并发/限速 `concurrentRate` | ✅ | ✅ | 对齐 |
| 源响应速度统计/排序 | ✅ SourceSpeedTracker | ❌ | ❌ 缺口 |
| JSC 池 / 空闲清理 | ✅ JSContextPool | 🟡 串行队列 + 超时；无池 | 🟡 性能差异 |
| JSC 执行超时 | ❓ 未见明确实现 | ✅ 12s（私有 API，见风险） | ✅ 我们更稳但合规有风险 |
| 远程书源后端 | ✅ | ❌（设计上不引入） | 🟡 有意取舍 |

## 3. 阅读器

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| 左右分页（TextKit） | ✅ | ✅ | 对齐 |
| 双页 / iPad 横屏 | ✅ ReaderTwoPageRenderer | ❌ | ❌ 明显缺口 |
| 翻页动画（页卷曲） | ✅ PageCurlDriver | ❌ | ❌ |
| 音量键翻页 | ✅ | ❌ | ❌ |
| 滚动阅读 | ✅ WKWebView + reader.js | 🟡 UITextView 整章 | 🟡 无 7 章窗口/锚点 |
| 跨章无缝 | ✅ 预取/占位/重建 | 🟡 过渡页重载 | 🟡 |
| 章节预取 | ✅ | 🟡 相邻章节预取有限 | 🟡 |
| 章节标题设计器 | ✅ 可视化 SPA（8 类元素/图层/撤销/资源） | 🟡 对齐/大小/分隔线/花饰 | ❌ 高级设计器缺失 |
| HTML 章节标题快照 | ✅ | ❌ | ❌ |
| 正文图片附件 | ✅ NSTextAttachment | ❌ 文本阅读器无内嵌图 | ❌ |
| 阅读背景图/模糊 | ✅ | ❌ 纯色主题 | ❌ |
| 段评气泡 | ✅ SVG 气泡/热评/本章说/作家说 | 🟡 段末 💬 气泡 + 段评面板；无热评/本章说/作家说/SVG 皮肤 | 🟡 |
| 章末评论 | ✅ | ✅ 列表/分页/点赞/回复/@ | ✅ 对齐/部分更强 |
| 划线/笔记 | ✅ | ✅ 分页 + 滚动模式 | ✅ |
| 高亮规则 | ✅ 17 字段 + `.qihighlight` 导入 | 🟡 关键词/正则 + 颜色；无导入导出 | 🟡 |
| 批注锚点/稳定坐标 | ✅ ReaderStableTextCoordinate | 🟡 UTF-16 章内偏移 | 🟡 重排后锚点稳定性较弱 |
| 阅读统计/目标 | ✅ 时长/书籍/年目标 | ❌ | ❌ |
| 睡眠定时 | ✅ TtsSleepTimer | ❌ | ❌ |
| 阅读主题 | ✅ 内置 + 自定义 + `.qitheme/.qipreset/.red` | 🟡 3 套内置主题 | ❌ 主题生态缺失 |
| 自定义字体 | ✅ 导入字体 | ❌ 宋体/苹方 | ❌ |
| 排版参数 | ✅ 丰富（背景/边距/两端对齐等） | ✅ 字号/行距/段距/边距/标题 | 🟡 |
| PDF | ✅ PDFKit | ✅ PDFKit + 按页 TTS + 句级高亮 | ✅ 朗读更强 |
| EPUB | ✅ 本地书支持 | ✅ 富文本 HTML/CSS/图片 + 分页/滚动 + 图片查看器 | ✅ |
| 漫画 | ✅ 分页 + Webtoon + 缩放 | ✅ CBZ/ZIP 分页 + 纵向长图 + 缩放 | 🟡 无 Webtoon 专项优化 |
| 本地 RAR/7z 导入 | ✅ | ❌ 仅 TXT/EPUB/PDF/CBZ/ZIP | ❌ |
| 文件管理器 | ✅ 内置 | ❌ 依赖系统文件导入 | ❌ |
| 阅读进度 | ✅ | ✅ | 对齐 |
| 目录/书签/笔记/段评/章末评论入口 | ✅ | ✅ | 对齐 |
| 换源 | ✅ | ✅ 聚合搜索换源 | ✅ |

## 4. TTS / AI

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| 系统 TTS | ✅ | ✅ | 对齐 |
| HTTP TTS（模板/POST/`@js:`） | ✅ | ✅ | 对齐 |
| WebSocket TTS | ✅ 真流式 + 二进制帧 | 🟡 文本帧 → 累积音频 → 落盘播放 | 🟡 非 PCM 流式 |
| 音频缓存 | ✅ | ✅ | 对齐 |
| Now Playing / 锁屏控制 | ✅ | ✅ | 对齐 |
| 多角色（旁白/对话） | ✅ | ✅ | 对齐 |
| 逐角色音色/音高 | ✅ | ✅ 启发式 + 自动分配 | ✅ |
| AI 角色归属（LLM） | ✅ OpenAI 兼容 + JSON Schema + 批处理 + 缓存 | ❌ 本地启发式 | ❌ 明显缺口 |
| AI Key Keychain | ✅ | ❌ | ❌ |
| TTS 登录 UI（loginUrl/loginUi/loginCheckJs） | ✅ | 🟡 `loginUrl` 登录页 + Cookie 提取已接；`loginUi` 表单与完整 `loginCheckJs` 未接 | 🟡 |
| 句级高亮 | ✅ | ✅ 分页/滚动/EPUB/PDF | ✅ 覆盖更全 |
| 睡眠定时 | ✅ | ❌ | ❌ |
| PCM 流式输出 | ✅ AVAudioEngine | ❌ AVAudioPlayer 文件播放 | 🟡 首句延迟更高 |
| 后台播放 | ✅ | ✅ `UIBackgroundModes=audio` | 对齐 |

## 5. 同步 / 备份 / 安全

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| 备份容器 | `.qibackup` ZIP（未加密） | `.zjbk` ZIP，可选 AES-GCM | ✅ 加密更强 |
| 备份分类 | 20+ 类（分组/阅读时长/替换规则/主题/字体/背景/标题资源/Cookie 等） | 8 类（书架/书源/设置/TTS/批注/段评/章末评论/清单） | ❌ 分类少 |
| 备份本地书正文 | ✅ 可选 | ❌ 只存元数据 | ❌ |
| WebDAV | ✅ 目录镜像增量 | 🟡 上传/下载最新 `.zjbk` + 独立评论文件；无增量镜像 | 🟡 |
| 评论独立同步 | ✅ 远程后端 | ✅ `zhijian-comments.json` 双向合并 + 墓碑 | ✅ |
| iCloud | ✅ 文档容器 + 自动备份频率 | 🟡 KVS 设置/进度/评论；Drive 镜像需签名 | 🟡 |
| 自动备份 | ✅ never/onExit/daily/weekly | ❌ 手动 | ❌ |
| 远程后端 | ✅ 控制面/内容面 | ❌ | 🟡 取舍 |
| Cookie 安全 | ⚠️ 进备份；PSL 支持 | ⚠️ 本地 JSON；备份不含 Cookie | 🟡 各有风险 |
| WebDAV 密码 | ⚠️ 明文 | ⚠️ 明文（UI 提示） | 🟡 都需 Keychain |
| AI Key | ✅ Keychain | N/A | — |
| 备份加密 | ❌ | ✅ PBKDF2-SHA256 120k + AES-GCM | ✅ 我们更好 |
| ATS | ⚠️ 任意加载 | ⚠️ 任意加载 | 🟡 都需审核说明 |
| TLS 信任 | ⚠️ 存在 trust-all 实现（可能死代码） | ✅ 无 trust-all | ✅ 更安全 |
| 硬编码 AES Key/IV | ❌ 存在（远程 token） | ✅ 无 | ✅ 更安全 |
| WebView 桥攻击面 | ⚠️ prompt 伪 RPC + 整页 HTML 捕获 | 🟡 有限 message handler | ✅ 更小 |
| 隐私清单 | ❓ | ✅ `PrivacyInfo.xcprivacy` | ✅ |
| 私有 API | 未见 | ⚠️ JSC 超时 dlsym 私有 API | ❌ 上架风险 |

## 6. 数据 / 生态 / 发布

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| 书架分组/网格列数 | ✅ | ❌ 仅网格 | ❌ |
| 阅读统计/目标 | ✅ | ❌ | ❌ |
| 发现页 | ✅ | ❌ | ❌ |
| 文件管理器 | ✅ | ❌ | ❌ |
| URL Scheme（qireader:// / yuedu://） | ✅ | ❌ | ❌ |
| 主题/预设/气泡/高亮包导入 | ✅ `.qitheme/.qipreset/.qibubble/.qihighlight/.cmts/.styles/.red` | ❌ 仅本地高亮规则 | ❌ 生态差距最大 |
| 书源导入 | ✅ JSON/URL/剪贴板/QR | ✅ JSON/URL/剪贴板 | ✅ 对齐 |
| 书源导出/编辑/分组 | ✅ | ❌ | ❌ |
| 章节磁盘缓存 | ✅ `ChapterCache` | 🟡 仅内存缓存 | ❌ 离线/省流弱 |
| 图片缓存 | ✅ ImageCache/MangaImageCache | 🟡 AsyncImage（系统缓存） | 🟡 |
| 章节标题资源/字体/背景管理 | ✅ | ❌ | ❌ |
| App Icon / 启动屏 / 隐私清单 | 未知（IPA 无签名） | ✅ 2.1 已就位 | ✅ |
| 签名/TestFlight | 样本未签名 | 未签名 Archive + IPA；待正式签名 | 🟡 双方都未签 |
| CI | 未知 | GitHub Actions 已归档（待 workflow scope） | ✅ |

## 7. 主观对齐度（按当前代码，非功能宣传）

| 领域 | 估计对齐度 | 说明 |
|---|---|---|
| 书源引擎 | **75–80%** | 规则/JS/兼容层强；登录 UI、发现、替换规则、jsLib、DNS 代理缺 |
| 阅读器 | **60–65%** | 分页/滚动/EPUB/PDF/漫画齐；双页/翻页动画/音量键/HTML 标题/图片/背景/统计缺 |
| TTS | **75%** | 系统/HTTP/WS/多角色/高亮齐；LLM 角色、睡眠定时、PCM 流式缺 |
| 同步/备份 | **65%** | 加密与评论同步更强；分类、本地书正文、iCloud 文档、自动备份、增量镜像弱 |
| 本地书 | **80%** | TXT/EPUB/PDF/CBZ/ZIP 齐；RAR/7z 导入、文件管理器缺 |
| 生态/主题/设置 | **35–40%** | 无主题包/字体/背景/统计/分组/URL Scheme |
| 安全/合规 | **70%** | 无 trust-all/硬编码密钥，备份加密；JSC 私有 API、ATS、明文 WebDAV 密码待解 |
| **综合** | **约 65–70%** | “能读、能听、能同步”，但“生态与高级排版”差距明显 |

## 8. 优先补齐建议（按投入产出）

### P0（最影响“像栖阅”）
1. **书源登录 UI**：`loginUrl` 打开 WebView、`loginUi` 原生表单、`loginCheckJs` + 登录态持久化。
2. **发现/Explore**：`exploreUrl` + `ruleExplore` 分类/筛选/信息流。
3. **替换规则 + 章节规则**：正文清洗、广告去除、目录修正。
4. **章节磁盘缓存**：目录/正文/图片落 Caches，离线阅读与省流。
5. **书架分组 + 阅读统计**：分组、阅读时长、目标。
6. **阅读器高级排版**：双页、翻页动画/音量键、HTML 章节标题设计器、正文图片/背景。
7. **TTS 睡眠定时 + 可选 LLM 角色**。

### P1（生态与同步）
8. 主题/预设/高亮/气泡包导入导出（至少 `.qibubble`/`.qihighlight` JSON）。
9. 书源编辑/导出/分组；搜索分页/取消/缓存。
10. iCloud 文档容器 + 自动备份频率；WebDAV 目录增量镜像。
11. 本地书正文/漫画/PDF 纳入备份；WebDAV 密码迁移 Keychain。
12. URL Scheme + 文档类型扩展（pdf/cbz/zip/rar/7z）。

### P2（体验/性能）
13. `jsLib` 共享脚本、DNS/代理覆盖、源响应速度排序。
14. 图片/章节缓存 LRU、JSC 池、搜索取消。
15. 阅读统计图表、段评热评/本章说样式。

## 9. 我们明确更好的地方

- **备份加密**：PBKDF2-HMAC-SHA256 120k + AES-GCM；栖阅备份是未加密 ZIP。
- **fastjson/Gson 兼容**：栖阅报告明确“无存根”，我们已实现并通过自检。
- **JSC 执行超时**：12s 中断死循环（代价是私有 API 合规风险）。
- **四阅读器统一句级高亮**：分页/滚动/EPUB/PDF 都接 TTS。
- **评论同步冲突处理**：`updatedAt` + 删除墓碑 + 冲突计数；栖阅是远程后端模型。
- **无远程后端、无硬编码 AES Key、无 trust-all**：攻击面更小。
- **RAR/7z 通过系统 libarchive**：不引入 Unrar/SevenZip 二进制依赖。
- **发布物料**：Icon/启动屏/隐私清单/未签名 IPA/CI 已就绪。

## 10. 结论

如果目标是 **“覆盖栖阅 80% 日常阅读场景”**，当前差距主要集中在 **登录/发现/规则治理/高级排版/主题生态**；如果目标是 **“功能逐项对齐”**，还需要补齐 P0/P1 约 12 项，工作量估计为当前工程的 **40–60%**。

建议下一阶段先做 **书源登录 UI + 发现页 + 替换规则 + 章节磁盘缓存**（这四项直接决定“书源好不好用”），再做 **双页/标题设计器/统计/主题包**（决定“像不像栖阅”）。
