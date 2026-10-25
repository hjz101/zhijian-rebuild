# 指尖阅读（Zhijian）

**iOS 原生阅读器**：Legado 兼容书源引擎 + 四阅读器（分页/滚动/EPUB/PDF/漫画）+ 系统·HTTP·WS·PCM TTS + 加密备份/WebDAV/iCloud 同步 + 评论生态。零第三方依赖、零内置内容、无远程后端。

![书架](docs/screenshots/lead-01-shelf.png)
![分页阅读](docs/screenshots/lead-05-reader.png)
![远程书源](docs/screenshots/lead-06-reader-remote.png)
![朗读](docs/screenshots/lead-10-tts-fixed.png)

## 功能总览

| 模块 | 能力 |
|---|---|
| **书源引擎** | Legado `BookSource` 35 字段；规则链 `{{}}/@put/@get/索引/##`；CSS/XPath/JSONPath/正则/JS/WebJs；`java.*` 兼容（网络/编码/加密/压缩/jsoup/fastjson/Gson）；登录（loginUi 原生表单 / loginUrl / `@js:` / 登录态持久化）；发现（JS/JSON/行文本 + 分类 + 网格/列表）；替换规则 / 章节规则 / jsLib；书源编辑/分组/导出/去重/体检/批量测试/速度统计；DNS 代理（HTTP/SOCKS5）；HTTPS 优先 |
| **阅读器** | native TextKit 分页；双页 / 4 种翻页动画 / 音量键翻页；滚动模式（长章自动分页）；章节标题设计器 + HTML 快照；正文图片（`<img>` 附件 + 点击全屏 + json 协议 headers）；阅读背景图；6 套内置主题 + 自定义配色（5 色 + chrome）；主题包（.zjtheme/.red/.qitheme/.qibubble）；自定义字体；简繁转换；高亮规则；批注稳定坐标 |
| **TTS** | 系统 AVSpeechSynthesizer；HTTP TTS（模板/POST/`@js:`）；WebSocket 流式（PCM 分帧/文本帧）；多角色（旁白/对话 + 逐角色音色）；LLM 角色识别（OpenAI 兼容 + Keychain）；睡眠定时；句级高亮（分页/滚动/EPUB/PDF）；Now Playing / 后台播放 |
| **评论** | 段评气泡（颜色/圆角/图标可调）+ 热评 Top3；章末评论（点赞/回复/@/分页/墓碑合并）；独立 WebDAV 评论同步 |
| **同步/备份** | `.zjbk` 加密备份（PBKDF2-SHA256 120k + AES-GCM，可选含本地书正文）；WebDAV 增量镜像（PROPFIND 比对/冲突保护）；iCloud 自动备份（onExit/daily/weekly）+ 云端恢复；Keychain 凭据；Cookie eTLD+1（精简 PSL） |
| **本地书** | TXT（编码探测+自动分章）/ EPUB（富文本 HTML/CSS/图片 + 分页/滚动）/ PDF（按页 TTS）/ 漫画（CBZ/ZIP/RAR/7z 分页/长图）；压缩包自动识别；文件管理器（浏览/导入/删除/重命名/移动/复制） |
| **统计** | 日/周/连续/书籍/年度目标；30 日趋势柱状图 |

## 构建

要求：Xcode 15+，iOS 17 SDK。零 SPM 依赖。

```bash
# 模拟器 Debug
xcodebuild -project Zhijian.xcodeproj -scheme Zhijian \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/zj build

# 真机 Release Archive（未签名）
xcodebuild -project Zhijian.xcodeproj -scheme Zhijian \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath /tmp/Zhijian.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## 自检与调试

```bash
# 统一回归自检（40 项：规则/替换/目录/加密/镜像 diff/稳定坐标/简繁/图片协议/PSL/外部格式…）
xcrun simctl launch booted com.zhijian.reader -selfTestSuite
# 真实书源回归（搜索+发现，报告写 source-regression-report.txt）
xcrun simctl launch booted com.zhijian.reader -selfTestSuite -sourceRegression
```

完整调试参数见 [docs/BACKLOG.md](docs/BACKLOG.md)；常用：`-seed*`（示例数据）、`-exploreOpenFirst`、`-scrollMode`、`-palette=anmo`、`-webViewJSExecTest`、`-pcmPlayerTest`。

## 架构

```
Zhijian/
├── App/                  # 入口、RootView、AppEnvironment（依赖容器）
├── Core/
│   ├── Models/           # Legado 模型、书/章节、TTS/WebDAV/备份、协议
│   ├── Parsing/          # HTMLDocument / CSSSelector / XPathQuery / JSONPath / HtmlFormatter
│   ├── Rules/            # RuleEngine（规则链/CSS/XPath/JSON/JS/正则/变量）
│   ├── Runtime/          # JSRuntime + Java 兼容 + JSVirtualMachinePool + WebViewJSExecutor
│   ├── Pipeline/         # SourcePipeline（search/bookInfo/toc/content + HTTP/Cookie/限速/代理）
│   ├── Reader/           # PaginationEngine / ReaderViewModel / BookContentService / 主题/简繁/稳定坐标
│   ├── TTS/              # TTSController / HTTPTTSDriver / WebSocket / PCMStreamPlayer / LLM
│   ├── Sync/             # BackupService / WebDAVClient / WebDAVMirror / AutoBackup / ZipArchive
│   ├── Security/         # KeychainStore / BackupCrypto
│   └── Store/            # BookStore / SourceStore / LocalLibrary / 导入 / 统计
├── Features/             # Shelf / Sources / Reader / TTS / Settings
├── Design/               # ZJ 设计令牌（seed 强调色外观）
└── Resources/            # packages_stub.js / jsoup_bridge.js / 示例书源/示例书
```

## 文档

| 文档 | 说明 |
|---|---|
| [docs/QIREADER-COMPARISON.md](docs/QIREADER-COMPARISON.md) | 与栖阅逐项对比（对齐度 ~85%） |
| [docs/THEME-V2.md](docs/THEME-V2.md) | 主题系统 v2 方案 |
| [docs/COMPLIANCE.md](docs/COMPLIANCE.md) | 上架合规复查清单 + 审核备注模板 |
| [docs/DEVICE-TEST-CHECKLIST.md](docs/DEVICE-TEST-CHECKLIST.md) | 真机验证清单 |
| [docs/KNOWN-LIMITATIONS.md](docs/KNOWN-LIMITATIONS.md) | 已知限制（诚实清单） |
| [PUBLIC_SOURCE_SCOPE.md](PUBLIC_SOURCE_SCOPE.md) | 开源边界 |
| [LICENSE](LICENSE) | AGPL-3.0 |

## 贡献指南

- **书源兼容修复**：书源格式为 Legado 公开规范；新源兼容问题欢迎 PR（附源 JSON + 失败诊断）。
- **回归**：改动后跑 `-selfTestSuite`（40 项）与真实书源回归，结果贴 PR。
- **测试**：当前以调试自检为回归基线；XCTest target 迁移路径见 BACKLOG（欢迎贡献）。
- **i18n**：`LocalizationManager.tr(key)` 文案表逐条迁移中。
- **边界检查**：`python3 tool/check_public_source.py` 必须通过（禁止个人路径/密钥/逆向报告引用）。

## 合规

- 自有代码：书源格式按 Legado 公开规范实现，未复制 QiReader / Legado / origo-x 代码或资源。
- 不预置书源、不内置内容；用户导入的书源与内容版权归原站/作者。
- 无账号体系、无广告、无内购、无数据收集（隐私清单见 `Zhijian/PrivacyInfo.xcprivacy`）。
