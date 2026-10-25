# 指尖阅读 2.1 vs 栖阅（QiReader）详细对比

> 对照依据：栖阅（QiReader）行为规格（360 个源文件、25,294 个函数名、364 个 ObjC 类，逆向报告不随本仓库分发）与本仓库当前代码（**130 Swift 文件 / 35,445 行**）。
> 图例：✅ 对齐或更好 · 🟡 部分实现/语义有差异 · ❌ 缺失。
> 可执行任务清单见 [BACKLOG.md](BACKLOG.md)（P0–P4，P0/P1/P2/P3 已完成）。

## 0. 一句话结论

- **骨架已对齐且 P0–P3 全部落地**：Legado 书源模型与规则（含登录/发现/替换/章节规则/jsLib/代理）、native TextKit 分页 + 双页 + 翻页动画/音量键、HTML 标题设计器、正文图片/背景、主题包/自定义字体、系统/HTTP/WS/PCM 流式 TTS、睡眠定时/LLM 角色、备份加密/WebDAV 增量镜像/iCloud 自动备份/Keychain、段评热评/章末评论、TXT/EPUB/PDF/漫画、RAR/7z、文件管理、URL Scheme、稳定坐标。
- **当前主要差距**集中在：滚动阅读虚拟窗口、Cookie eTLD+1(PSL)、部分 `java.*` 边界 API、RAR 真实样本回归、WebView 源拦截窗口、高级排版（SVG 气泡皮肤/作家说）、`qibubble/.red` 等外部主题格式、以及上架合规（签名/私有 API/ATS）。
- **反向优势**：备份 AES-GCM 加密、fastjson/Gson 存根、RAR/7z libarchive、JSC 超时（Debug）、四阅读器统一 TTS 句级高亮、评论墓碑合并、无远程后端/无硬编码密钥/无 trust-all。

## 1. 总体规模与架构

| 维度 | 栖阅 QiReader | 指尖阅读 2.1 | 差距 |
|---|---|---|---|
| 代码规模 | 360 Swift 文件 / 25,294 函数名 / 178 应用类 | 130 Swift 文件 / 35,445 行 | 🟡 约为其 1/3 文件量 |
| 最低系统 | iOS 17 | iOS 17 | ✅ |
| UI | SwiftUI + UIKit | SwiftUI + UIKit（栖阅式三 Tab/玻璃卡片/5 套配色/随配色图标） | ✅ |
| 分页内核 | native TextKit | native TextKit（单页/双页、4 种翻页动画、音量键） | ✅ |
| 滚动内核 | WKWebView + reader.js（7 章窗口） | UITextView 整章滚动 | 🟡 无虚拟窗口/锚点补偿 |
| 第三方依赖 | SwiftSoup/Kanna/SwiftyJSON/ZIPFoundation/Unrar/SevenZip/Sextant 等 | 无 SPM 依赖（系统框架 + 自研 + libarchive dlsym） | 🟡 功能广度换依赖轻量 |
| 二进制体积 | 28.4 MB | ~12 MB（未签名 IPA） | ✅ 更小 |
| 远程后端 | 有（25+ accessToken 端点 + WebSocket） | 无（设计上不引入） | 🟡 功能少但攻击面小 |

## 2. 书源引擎（Legado 兼容）

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| BookSource 35 字段 | ✅ | ✅（含 loginUrl/loginUi/loginCheckJs/jsLib/header/explore） | 对齐 |
| 规则链 / `{{}}` / `@put` / `@get` / 索引 / `##` | ✅ | ✅ | 对齐 |
| CSS / XPath / JSONPath / 正则 / JS / WebJs | ✅ | ✅ | 对齐 |
| `java.*` 网络/编码/加密/压缩/文件 | ✅ 绝大多数 | ✅ 大部分 | 🟡 少量边界 API 未覆盖 |
| jsoup / JXDocument | ✅ | ✅（jsoup_bridge.js） | 对齐 |
| fastjson / Gson | ❌ 无存根 | ✅ 已实现 JSON/JSONObject/JSONArray、Gson/JsonParser | ✅ 我们更好 |
| ZIP 读取/解包 | ✅ | ✅（自研 ZipWriter/Reader） | 对齐 |
| RAR / 7z 读取 | ✅ 原生库 | ✅ libarchive 弱链接（7z 实测，RAR 待真实样本回归） | 🟡 |
| `@webjs` / `ruleContent.webJs` | ✅ | ✅ | 对齐 |
| `sourceRegex` / XHR-fetch 拦截 | ✅ BackstageWebView 完整拦截 | ✅ 离屏 WebView 注入拦截（约 2.5s 窗口） | 🟡 窗口/请求改写不足 |
| `loginCheckJs` | ✅ | ✅ 每次响应后执行 | 对齐 |
| `loginUrl` + `loginUi` 原生登录 | ✅ 38 方法、6 种控件 | ✅ loginUi 表单（text/password/toggle/select/button）+ loginUrl WebView/`@js:` 脚本 + 登录态持久化 | ✅（样式子集） |
| Cookie 持久化 | ✅ PSL eTLD+1 + CookieBridge | ✅ `cookies.json` 域级持久化 + 跨管线共享 | 🟡 无 PSL |
| 登录态 `loginInfo` 持久化 | ✅ 按源保存 | ✅ `source_login.json` + 注入管线 | ✅ |
| 发现/Explore | ✅ 分类/筛选/信息流/网格 | ✅ 分类（JS/JSON/行文本）+ 列表 + 分页 + 失败自动回退 | 🟡 无筛选/信息流/网格 |
| 搜索多源并发 | ✅ | ✅ | 对齐 |
| 搜索分页/取消/结果缓存 | ✅ | ✅ 加载更多/取消/180s 缓存/去重合并 | ✅ |
| 替换规则（13 字段） | ✅ | ✅ 正则/字面量/作用域/顺序/超时/导入导出 | 🟡 少规则分组 |
| 章节规则（目录/正文/广告清理） | ✅ | ✅ 去重/去空/卷名/排序/标题正则（全局+按源） | ✅ |
| 书源分组/编辑/导出 | ✅ | ✅ 单条编辑（JSON/分组/启停）、分组筛选、导出、去重 | ✅ |
| 书源全流程/批量测试 | ✅ | ✅ 四阶段体检 + 批量测试 + 诊断快照 | ✅ |
| `jsLib` 共享脚本 | ✅ SharedJsScope | ✅ 内联/远程 + 磁盘缓存 + 诊断 | ✅ |
| DNS 覆盖 / 代理（http/socks） | ✅ 本地 CONNECT 隧道 | ✅ 全局 HTTP/SOCKS5 代理（仅本 App） | 🟡 无按源隧道 |
| 并发/限速 `concurrentRate` | ✅ | ✅ | 对齐 |
| 源响应速度统计/排序 | ✅ SourceSpeedTracker | ✅ SourceSpeedStore（均值/次数/最近，持久化） | ✅ |
| JSC 池 / 空闲清理 | ✅ JSContextPool | ✅ JSVirtualMachinePool + 按源 pipeline 复用 + 内存警告回收 | ✅ |
| JSC 执行超时 | ❓ 未见明确实现 | ✅ Debug 12s 私有 API；Release 不加载私有符号（看门狗） | ✅ 更稳但合规注意 |
| 远程书源后端 | ✅ | ❌（设计上不引入） | 🟡 有意取舍 |

## 3. 阅读器

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| 左右分页（TextKit） | ✅ | ✅ | 对齐 |
| 双页 / iPad 横屏 | ✅ ReaderTwoPageRenderer | ✅ 横屏双栏 + 旋转保进度（`-forceTwoPage` 验证） | ✅ |
| 翻页动画 | ✅ PageCurlDriver | ✅ 平移/仿真/淡入/无动画 | ✅ |
| 音量键翻页 | ✅ | ✅ MPVolumeView 隐藏 + 音量还原 | ✅ |
| 滚动阅读 | ✅ WKWebView + reader.js | 🟡 UITextView 整章 | 🟡 无 7 章窗口/锚点 |
| 跨章无缝 | ✅ 预取/占位/重建 | 🟡 过渡页重载 + 相邻章节预取 | 🟡 |
| 章节预取 | ✅ | 🟡 相邻章节预取（限内存缓存） | 🟡 |
| 章节标题设计器 | ✅ 可视化 SPA（8 类元素/图层/撤销/资源） | ✅ 简化版（文字/线条/装饰/图片，位置/字号/颜色/透明度，导入导出） | 🟡 无图层/撤销 |
| HTML 章节标题快照 | ✅ | ✅ 离屏 WKWebView 快照 + LRU | ✅ |
| 正文图片附件 | ✅ NSTextAttachment | ✅ `<img>` 提取 + 下载缓存 + 附件 + 点击全屏 | ✅ |
| 阅读背景图/模糊 | ✅ | ✅ 相册选图 + 模糊 + 不透明度 | ✅ |
| 段评气泡 | ✅ SVG 气泡/热评/本章说/作家说 | ✅ 段末气泡（颜色/圆角/图标可调）+ 段评面板 + 热评 Top3 | 🟡 无 SVG 皮肤/作家说 |
| 章末评论 | ✅ | ✅ 列表/分页/点赞/回复/@ + 热评 | ✅ |
| 划线/笔记 | ✅ | ✅ 分页 + 滚动模式 | ✅ |
| 高亮规则 | ✅ 17 字段 + `.qihighlight` | ✅ 关键词/正则 + 颜色 + 导入导出（`.qihighlight` JSON） | 🟡 字段子集 |
| 批注锚点/稳定坐标 | ✅ ReaderStableTextCoordinate | ✅ StableTextCoordinate（前文 24 字符锚点 + 重排重定位） | ✅ |
| 阅读统计/目标 | ✅ | ✅ 今日/周/连续/书籍/年度目标/30 日趋势 | ✅ |
| 睡眠定时 | ✅ TtsSleepTimer | ✅ 关/10/20/30/60 分 | ✅ |
| 阅读主题 | ✅ 内置+自定义+`.qitheme/.qipreset/.red` | ✅ 内置 3 套 + `.zjtheme` 包 + 从当前设置创建 | 🟡 无 `.red` 导入 |
| 自定义字体 | ✅ 导入字体 | ✅ CTFontManager 注册 TTF/OTF/TTC + 字体管理页 | ✅ |
| 排版参数 | ✅ 丰富 | ✅ 字号/行距/段距/边距/标题 + 双页/动画/背景 | ✅ |
| PDF | ✅ PDFKit | ✅ PDFKit + 按页 TTS + 句级高亮 | ✅ 朗读更强 |
| EPUB | ✅ | ✅ 富文本 HTML/CSS/图片 + 分页/滚动 + 图片查看器 | ✅ |
| 漫画 | ✅ 分页+Webtoon+缩放 | ✅ CBZ/ZIP/RAR/7z 分页 + 纵向长图 + 缩放 | 🟡 无 Webtoon 专项 |
| 本地 RAR/7z 导入 | ✅ | ✅ 自动识别漫画/TXT/EPUB | ✅ |
| 文件管理器 | ✅ 内置 | ✅ Documents 浏览/导入/删除/重命名/移动/复制 | ✅ |
| 阅读进度 | ✅ | ✅ | 对齐 |
| 目录/书签/笔记/段评/章末评论入口 | ✅ | ✅ | 对齐 |
| 换源 | ✅ | ✅ 聚合搜索换源 | ✅ |

## 4. TTS / AI

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| 系统 TTS | ✅ | ✅ | 对齐 |
| HTTP TTS（模板/POST/`@js:`） | ✅ | ✅ + 自动 Content-Type | ✅ |
| WebSocket TTS | ✅ 真流式 + 二进制帧 | ✅ PCM 分帧流式（PCMStreamPlayer，首帧即播）+ 文本帧兼容 | ✅ |
| 音频缓存 | ✅ | ✅ | 对齐 |
| Now Playing / 锁屏控制 | ✅ | ✅ | 对齐 |
| 多角色（旁白/对话） | ✅ | ✅ | 对齐 |
| 逐角色音色/音高 | ✅ | ✅ 启发式 + 自动分配 | ✅ |
| AI 角色归属（LLM） | ✅ OpenAI 兼容 + JSON Schema + 批处理 + 缓存 | ✅ OpenAI 兼容 + Keychain Key + 章节缓存 + 失败回退 | ✅（无批处理） |
| AI Key Keychain | ✅ | ✅ | ✅ |
| TTS 登录 UI | ✅ | ✅ 内置登录面板 + loginUi 按钮 action 逐个执行 | ✅ |
| 句级高亮 | ✅ | ✅ 分页/滚动/EPUB/PDF | ✅ 覆盖更全 |
| 睡眠定时 | ✅ | ✅ | ✅ |
| PCM 流式输出 | ✅ AVAudioEngine | ✅ AVAudioEngine 引擎播放 + PCM 分帧 | ✅ |
| 后台播放 | ✅ | ✅ `UIBackgroundModes=audio` | 对齐 |

## 5. 同步 / 备份 / 安全

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| 备份容器 | `.qibackup` ZIP（未加密） | `.zjbk` ZIP，可选 AES-GCM | ✅ 加密更强 |
| 备份分类 | 20+ 类 | 9 类（书架/书源/设置/TTS/批注/段评/章末评论/清单 + 可选本地书正文） | 🟡 分类少 |
| 备份本地书正文 | ✅ 可选 | ✅ 可选（EPUB/PDF/漫画/local_library） | ✅ |
| WebDAV | ✅ 目录镜像增量 | ✅ 增量镜像（PROPFIND 比对/只传变化/冲突保护） | ✅ |
| 评论独立同步 | ✅ 远程后端 | ✅ `zhijian-comments.json` 双向合并 + 墓碑 | ✅ |
| iCloud | ✅ 文档容器 + 自动备份频率 | ✅ KVS + Drive 镜像 + 自动备份（onExit/daily/weekly）+ 云端恢复 | ✅ |
| 自动备份 | ✅ | ✅ | ✅ |
| 远程后端 | ✅ | ❌ | 🟡 取舍 |
| Cookie 安全 | ⚠️ 进备份；PSL | ⚠️ 本地 JSON；备份不含 Cookie | 🟡 各有取舍 |
| WebDAV 密码 | ⚠️ 明文 | ✅ Keychain（未签名回退明文并提示） | ✅ |
| AI Key | ✅ Keychain | ✅ Keychain | ✅ |
| 备份加密 | ❌ | ✅ PBKDF2-SHA256 120k + AES-GCM | ✅ 我们更好 |
| ATS | ⚠️ 任意加载 | ⚠️ 任意加载（兼容书源）+ HTTPS 优先开关 | 🟡 都需审核说明 |
| TLS 信任 | ⚠️ 存在 trust-all | ✅ 无 trust-all | ✅ 更安全 |
| 硬编码 AES Key/IV | ❌ 存在 | ✅ 无 | ✅ 更安全 |
| WebView 桥攻击面 | ⚠️ prompt 伪 RPC | 🟡 有限 message handler | ✅ 更小 |
| 隐私清单 | ❓ | ✅ `PrivacyInfo.xcprivacy` | ✅ |
| 私有 API | 未见 | ⚠️ Debug 用 JSC dlsym 超时；Release 已禁用 | 🟡 上架需说明 |

## 6. 数据 / 生态 / 发布

| 能力 | 栖阅 | 指尖阅读 2.1 | 差距/说明 |
|---|---|---|---|
| 书架分组/网格列数 | ✅ | ✅ 分组 chip + 排序 + 网格/列表 + 列数 2–5 | ✅ |
| 阅读统计/目标 | ✅ | ✅ | ✅ |
| 发现页 | ✅ | ✅ | ✅ |
| 文件管理器 | ✅ | ✅ | ✅ |
| URL Scheme（qireader:// / yuedu://） | ✅ | ✅ `zhijian://`/`qireader://`/`yuedu://` 导入书源/主题/备份 | ✅ |
| 主题/预设/气泡/高亮包 | ✅ `.qitheme/.qipreset/.qibubble/.qihighlight/.red` | 🟡 `.zjtheme` / `.qihighlight` JSON / 气泡样式内建 | 🟡 无 `.qibubble/.red` |
| 书源导入 | ✅ JSON/URL/剪贴板/QR | ✅ JSON/URL/剪贴板 | ✅（无 QR） |
| 书源导出/编辑/分组 | ✅ | ✅ | ✅ |
| 章节磁盘缓存 | ✅ ChapterCache | ✅ 目录 TTL + 正文 + 200MB LRU + 管理页 | ✅ |
| 图片缓存 | ✅ ImageCache | ✅ ReaderImageStore 磁盘+内存 + 清理 | 🟡 内存上限待加 |
| 章节标题资源/字体/背景管理 | ✅ | ✅ 字体/背景/标题模板管理页 | ✅ |
| App Icon / 启动屏 / 隐私清单 | 未知 | ✅ 2.1 已就位 + 随配色图标 | ✅ |
| 签名/TestFlight | 样本未签名 | 未签名 Archive + IPA；待正式签名 | 🟡 双方都未签 |
| CI | 未知 | GitHub Actions 已归档（待 workflow scope） | ✅ |

## 7. 主观对齐度（按当前代码）

| 领域 | 估计对齐度 | 说明 |
|---|---|---|
| 书源引擎 | **85–90%** | 规则/JS/兼容层/登录/发现/替换/章节/jsLib/代理/速度齐；少量边界 API 与 PSL |
| 阅读器 | **85%** | 分页/双页/动画/音量键/标题设计器/图片/背景/统计齐；滚动虚拟窗口与 Webtoon 待 |
| TTS | **90%** | 系统/HTTP/WS/PCM/多角色/LLM/睡眠/高亮齐 |
| 同步/备份 | **90%** | 加密更强、增量镜像/自动备份/iCloud/Keychain 齐 |
| 本地书 | **95%** | TXT/EPUB/PDF/CBZ/ZIP/RAR/7z/文件管理齐；RAR 真实样本待回归 |
| 生态/主题 | **60%** | `.zjtheme`/字体/背景/气泡内建；`.qibubble/.red` 导入待 |
| 安全/合规 | **75%** | 无 trust-all/硬编码密钥/备份加密；JSC 私有 API（Release 已禁用）、ATS、签名待 |
| **综合** | **约 85%** | “能读、能听、能同步、能治理”，剩生态格式与发布合规 |

## 8. 剩余建议（按投入产出）

### R1（质量与可信度，本轮）
1. **文档纠偏**（已完成本表）：真实代码盘点逐项标 ✅/🟡。
2. **XCTest 目标**：`RuleEngine`/`JSBlock`/`PseudoURL`/`ReplaceRuleEngine`/`ChapterRuleEngine`/`BackupCrypto`/`WebDAVMirror.diff`/`StableTextCoordinate`/`TTSSegmenter` 单测。
3. **内存与长章稳定性**：图片内存 LRU、pipeline 超时回收、滚动分块加载。

### R2（对齐补缺）
4. Cookie eTLD+1（精简 PSL）。
5. 真实书源回归矩阵（3–5 个形态固化）。
6. `.qibubble/.red` 主题格式导入；SVG 气泡皮肤。

### R3（发布）
7. 合规复查清单 + ATS 说明；CI 放回 `.github/workflows/`（需 workflow scope）。
8. 正式签名 + TestFlight（需 Apple Team/证书）。

## 9. 我们明确更好的地方

- **备份加密**：PBKDF2-HMAC-SHA256 120k + AES-GCM；栖阅备份是未加密 ZIP。
- **fastjson/Gson 兼容**：栖阅报告明确“无存根”，我们已实现并通过自检。
- **四阅读器统一句级高亮**：分页/滚动/EPUB/PDF 都接 TTS。
- **评论同步冲突处理**：`updatedAt` + 删除墓碑 + 冲突计数。
- **无远程后端、无硬编码 AES Key、无 trust-all**：攻击面更小。
- **RAR/7z 通过系统 libarchive**：不引入 Unrar/SevenZip 二进制依赖。
- **凭据安全**：WebDAV/TTS Key 进 Keychain（未签名回退并提示）。
- **发布物料**：Icon/启动屏/隐私清单/未签名 IPA/CI 已就绪。

## 10. 结论

P0–P3 全部落地后，**综合对齐度约 85%**，日常阅读场景已基本对齐（阅读、听书、书源治理、同步、备份、本地书）。剩余差距集中在：滚动虚拟窗口（性能）、外部主题格式（`.qibubble/.red`）、Cookie PSL、RAR 真实样本回归、以及发布合规（签名/私有 API/ATS/CI）。下一步建议以 **R1 质量项（单测 + 内存/长章稳定性）** 为主。
