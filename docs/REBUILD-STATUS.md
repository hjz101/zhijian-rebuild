# 重建状态 · 2026-10-25

## 已完成（P0）

| 分线 | 交付 | 验收 |
|---|---|---|
| Lead（App/Store/UI） | 工程脚手架（Xcode 16 同步目录）、AppEnvironment、BookStore/SourceStore/SettingsStore、Shelf/Sources/Settings、TXT 导入、离线示例书、调试参数 | 模拟器构建/安装/启动；搜索→详情→加入书架全链路 |
| engine | `CodecSupport`（AES/DES/3DES、MD5/SHA、HMAC、GZIP、RSA）、`packages_stub.js`（Packages/javax.crypto/java.security/java.util/java.io/net/hutool/okhttp/JsonPath/Jsoup）、`JSRuntime+Native/JavaCompat/Jsoup`、`SourcePipeline` loginCheckJs/限速/诊断、TOC 归一化 | 59/59 CLI 自测；真实《剑来》1,320 章 + 首章正文；构建通过 |
| reader | `PaginationEngine`、`ReaderViewModel`、`PagedReaderView`、`ScrollReaderView`、`ReaderSheets`、`ReaderScreen`、`BookContentService` | 本地/远程分页、跨章、主题/字号、目录、进度持久化 |
| tts-sync | 系统/多角色/HTTP TTS、`TTSSourceStore`、`TTSPlayerBar`、`TTSConfigView`、`.zjbk` 备份、WebDAVClient、`BackupView` | TTS 实测（系统朗读/HTTP mock）、备份 round-trip、WebDAV mock |

## 迁移自旧工程（用户自有代码）

- 解析器：HTMLDocument / CSSSelector / XPathQuery / JSONPath / HtmlFormatter
- 规则引擎：RuleEngine（已由 engine 扩展）
- JS 运行时：JSRuntime（已由 engine 扩展）
- 管线：SourcePipeline（已扩展）
- 设计令牌：Tokens.swift
- 资源：示例书源、示例 EPUB、主题包（未全部启用）

## 已完成（P1 第一批）

- 阅读增强：书签、划线、笔记（选区菜单 + 笔记编辑）、目录/书签/笔记三 Tab、换源。
- 持久化：`Application Support/Zhijian/annotations.json`。
- 本地书：EPUB 导入 + 富文本阅读（解包 XHTML/CSS/图片，WKWebView + 主题 CSS + 目录/章节切换/滚动进度），示例 EPUB 第 2 章含图片实测通过。
- PDF：导入、PDFKit 连续阅读、页码滑杆、页码目录、进度持久化；示例 PDF 3 页实测通过。
- 书源体检：四阶段测试（搜索/详情/目录/正文）、批量体检、错误/耗时、HTTP 流水与 JS console 诊断、复制；结果持久化。
- 引擎补强：fastjson/Gson、ZIP 读取/解包、离屏 WKWebView 兜底（`@webjs:`、`java.webView*`、`ruleContent.webJs`）；引擎自检 12 项全通过。
- 说明：`@webjs`/WebView 每次调用新建离屏 WKWebView（串行由 JS 线程保证），高频调用有性能开销；`sourceRegex` 通过注入 XHR/fetch 拦截脚本捕获响应并匹配正文；RAR/7z、验证码、startBrowser 仍 unsupported。
- 批量测试：多关键词 × 多源、深度四阶段开关、并发 1–4、报告分享/复制。
- 备份加密：`.zjbk` 可选 PBKDF2-HMAC-SHA256（120k）+ AES-GCM；恢复自动识别加密包并提示密码；WebDAV 上传共用该开关。自检：加密往返/错误密码拒绝/文件识别/恢复均通过。
- 漫画：CBZ/ZIP 导入 → 本地图片仓库 + manifest；TabView 横向分页、UIScrollView 缩放/双击、页码滑杆、页码目录、进度；示例 3 页实测通过。
- JSC 执行保护：通过 JavaScriptCore 私有 API（dlsym 弱链接）设置执行时间上限 12s；无限循环 2.1s 被中断并转为规则错误。
- RAR/7z：通过 iOS SDK `libarchive` 弱链接实现 list/read/extract，ZIP 优先、失败回退；`java.getZipStringContent/getZipByteArrayContent/unzipFile/getRarStringContent/get7zStringContent` 均可用；7z 实测 `entries=1 · 7z-hello`。
- Cookie 迁移：`cookies.json` 持久化 + 跨源共享；管理页查看/删除/清空/复制 Netscape 格式。
- iCloud：KVS 同步阅读设置与每本书进度（未签名时降级本地镜像并明确提示）；iCloud Drive 镜像在可用容器时复制 `.zjbk`，当前未签名构建显示不可用；已补 iCloud 容器 entitlement 与 `NSUbiquitousContainers`。
- EPUB 分页：CSS 多列 + JS 测量页数/横向分页；顶部显示「第 x/y 页」；点击左右/按钮翻页、跨章切换；长章 40 段实测 10 页，第 4 页定位正常。
- TTS 角色：引号归属（前置/后置「X说」）与提示语提取角色，逐角色分配系统语音+音高；设置页可覆盖。
- TTS 高亮：句子在章节内的 UTF-16 范围下发给阅读器；分页自动翻到当前句所在页、滚动模式自动滚动、EPUB 通过 JS 包裹 `<mark>` 并滚动定位（三种模式均实测截图）。
- HTTP TTS 登录：`loginUrl` 打开 WKWebView，抓取该域 Cookie 生成 Header 保存。
- WebSocket TTS：发送文本帧、累积二进制音频帧、done 后落盘播放；本地 ws 测试服务返回 151,644 字节 WAV 并成功播放。
- PDF 朗读：按页提取文本交给 TTS，当前句通过 `PDFPage.selection(for:)` + `PDFView.highlightedSelections` 高亮并自动翻页；PDF 朗读条可用。
- 阅读器打磨：章节标题设计器（对齐/1.0–1.8x/无装饰·分隔线·花饰）；自动高亮规则（关键词/正则/颜色，正文构建时着色）；滚动模式可选中并弹出「划线 / 笔记」，划线与笔记在滚动模式渲染；设置页新增标题与高亮入口。
- 段评：按「书 + 章节 + 正文段落」持久化；分页模式在段末显示 💬 气泡（数量），点击进入段评列表/发表/删除；段落范围按正文样式过滤（排除标题与装饰），保证气泡落在正文段；新增整章段评侧栏（滚动/分页通用）。
- 备份完整性：`.zjbk` 新增 `annotations.json`（书签/划线/笔记）、`paragraph_comments.json`、`chapter_comments.json`；恢复后批注/段评/章末评论计数回归通过。
- 章末评论：按书 + 章节持久化；章尾过渡页新增「章末评论 N」按钮，阅读页 `…` 菜单也可进入；列表/发表/删除完成。
- 评论同步：iCloud KVS 的 push/pull 增加段评、章末评论、批注/书签；未签名时仍走本地镜像。实测同步 8 条评论/批注。
- 同步冲突：评论新增 `updatedAt` + `deletedAt` 墓碑；合并按 id + 新时间戳优先，删除不会复活；拉取状态显示冲突数（实测 conflictCount=1、tombstoneCount=1）。
- 章末评论分页：每页 20 条，「加载更多（已显示 x/y 条）」，发表后自动展开到新评论；分页 API 实测 25 条 → 10/10/5。
- 评论互动：段评/章末评论均支持点赞（like 计数 + 本人态）、回复（replyToId，缩进展示）、@ 提及解析与高亮；点赞/回复参与 updatedAt 冲突合并。
- WebDAV 评论同步：独立 `zhijian-comments.json`，下载→按 updatedAt/墓碑合并→回传；本地 mock 实测同步 42 条评论、上传成功。
- 漫画纵向长图：`ReadingSettings.mangaScrollMode` 持久化；阅读器可切换横向分页/纵向连续滚动，页码随可见页更新，工具栏提供切换按钮。
- 图片查看器：EPUB 图片点击经 JS bridge 回传，native 全屏查看；本地/远端图片加载、捏合缩放、双击缩放、分享。

## 待办（P1/P2 剩余）

1. 阅读增强：图片查看器、章末评论、段评跨设备同步。
2. 引擎：验证码/交互式浏览器；RAR 真实样本回归；`sourceRegex` 请求头修改。
3. TTS：大模型角色识别（可选）、WebSocket 协议适配（JSON 文本帧/自定义鉴权）。
4. 同步：签名后验证 iCloud Drive 容器；本地书正文/漫画备份。
5. 本地书：条漫纵向模式、EPUB 分页图片适配。
6. 发布：App Icon、启动屏、隐私清单、未签名 Archive/IPA 已完成；待正式签名与 iCloud 容器实测。

## 验证截图

`docs/screenshots/lead-01-shelf.png` … `docs/screenshots/lead-10-tts-fixed.png`；分线截图见 `docs/READER-NOTES.md`、`docs/TTS-SYNC-NOTES.md`。
