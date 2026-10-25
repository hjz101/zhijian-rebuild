# 指尖阅读 vs origo-x / qysg（轻悦时光）对比与开源评估

> 对照日期：2026-10-25。指尖阅读当前 130 Swift 文件 / 约 3.5 万行（iOS 17+，无 SPM 依赖）。

## 1. 三个项目定位

| 项目 | 技术栈 | 定位 | 许可 |
|---|---|---|---|
| **origo-x**（miloquinn） | Flutter（Dart ~5.5 万行 / 166 文件）+ iOS/Android | 「本地阅读器开源版」：只保留本地 TXT/EPUB 阅读、书签笔记、系统 TTS、统计、主题字体；**裁剪掉书源引擎/AI/云同步/账号/支付** | AGPL-3.0（历史 MIT 保留） |
| **qysg / 轻悦时光**（autobcb） | Flutter + WebView 驱动书源 | 「WebView 书源 + JS bridge」方案：README + 模板 HTML（default/sb/bh/hy/tts）+ 桥协议；仓库本身是模板/文档而非完整 App 源码 | 未标注明确许可 |
| **指尖阅读（本工程）** | SwiftUI + UIKit（iOS 17+，零 SPM） | **完整实现**：Legado 书源引擎 + 四阅读器 + 多角色 TTS + 备份/WebDAV/iCloud + 评论 + 书源治理 | 未定（建议 MIT/Apache-2.0 或 AGPL 视目标） |

## 2. 指尖阅读相对这两个仓库的优势

| 能力 | origo-x（裁剪版） | qysg | 指尖阅读 |
|---|---|---|---|
| 书源引擎（Legado 35 字段/规则链/JS 兼容层） | ❌ 已裁剪 | ✅ WebView 脚本化（非 Legado 标准） | ✅ 完整 Legado 兼容 + fastjson/Gson 存根 + jsLib + 登录/发现/替换/章节规则 |
| 多源并发搜索/分页/取消/缓存 | ❌ | 🟡 视书源 | ✅ |
| 书源治理（编辑/分组/导出/去重/体检/批量测试/速度统计） | ❌ | ❌ | ✅ 独有 |
| 四阅读器统一 TTS 句级高亮 | 🟡 仅系统 TTS | ❌ | ✅ 系统/HTTP/WS/PCM + 多角色 + LLM + 睡眠定时 |
| 备份（AES-GCM 加密 + WebDAV 增量镜像 + iCloud 自动备份 + Keychain） | ❌ | ❌ | ✅ 独有且更强 |
| 评论生态（段评气泡/热评/章末评论/墓碑合并） | ❌ | 🟡 段评图片 | ✅ |
| 正文图片/背景/标题设计器/双页/翻页动画/音量键 | ❌ | 🟡 图片 json 扩展 | ✅ |
| 主题/字体/气泡/高亮/外部格式（.red/.qibubble/.zjtheme/.qihighlight） | 🟡 基础主题字体 | ❌ | ✅ |
| 本地书（TXT/EPUB/PDF/CBZ/RAR/7z + 文件管理） | ✅ TXT/EPUB | 🟡 | ✅ 覆盖更全 |
| 稳定坐标/长章分页/内存 LRU/自检套件 | 🟡 | ❌ | ✅ |
| 跨平台 | 🟡 Flutter 多平台 | ✅ 多平台 | ❌ 仅 iOS（本项目取舍） |

**结论：功能维度上，指尖阅读明显领先两个仓库**（origo-x 是有意裁剪、qysg 是模板生态）。指尖的核心价值 =「完整 Legado 生态 + 本地能力 + 同步/备份」，这正是 origo-x 裁剪掉的部分。

## 3. 指尖相对它们的短板（可借鉴）

1. **跨平台**：origo-x/qysg 是 Flutter，iOS/Android/桌面通吃；指尖仅 iOS。若要开源获更多贡献者，可考虑核心逻辑抽离或做 Android 版。
2. **多语言 i18n**：origo-x 有 10 种语言 l10n；指尖只有 zh-Hans。
3. **测试工程**：origo-x 有 RunnerTests（Swift）+ 公共 CI 检查；指尖目前用 `-selfTestSuite` 调试入口，无 XCTest target。
4. **qysg 的 WebView 方案**：书源在 WebView 里跑（天然规避 JSC 私有 API 合规问题、支持任意前端 JS 库）。指尖用 JSC 兼容层，Debug 依赖私有超时 API（Release 已禁用）。可借鉴：把「WebView 执行书源 JS」作为 JSC 的补充模式。
5. **qysg 正文图片协议**：`<img src="url,{json}">`（js/headers/imageDecode/段评图）较成熟；指尖已支持 `<img>` 附件 + 点击查看，但段评图片/图片解密函数未做。
6. **origo-x 的开源边界机制**：`PUBLIC_SOURCE_SCOPE.md` + `tool/check_public_source.py` + `public_source_manifest.json` 自动检查，防私密信息流入开源树——这是指尖开源前必须建立的。

## 4. 指尖阅读可以开源吗？——可以，且建议开源

### 有利因素（✅）
- 代码全部自有（Swift 原创，无第三方代码拷贝）；仅参考 Legado 书源格式（开源）与栖阅行为规格（未抄代码）。
- 无内置书源/内容/密钥：不含任何第三方内容、无硬编码 Token。
- 关键逻辑可用文档与自检说明；无账号体系，隐私面小。
- 与 origo-x 一样可做「功能完整开源」：指尖没有需要隐藏的服务端，**全部能力都在本地**，不存在 origo-x 那种「官方包含未开源功能」的割裂。

### 需要先做的事（开源前清理清单）
1. **License 选定**：建议 **AGPL-3.0**（与 origo-x 一致，保护书源生态不被闭源分叉）或 Apache-2.0（更宽松）。若含栖阅启发部分，注意栖阅本身未开源——但我们是「行为规格参考、代码自写」，无代码侵权。
2. **清敏感项**：删除 `dist/`（IPA/SHA256）、`docs/screenshots` 中可能含个人信息的图、`zhijian-rebuild-2.1.bundle`（含 git 历史）、个人路径（`/Users/a706/...`）在文档里的硬编码、`qireader` 逆向报告路径引用（`file:///Users/a706/...`）。
3. **建立开源边界检查**：仿 origo-x 加 `PUBLIC_SOURCE_SCOPE.md` + `tool/check_public_source.py`（防 secrets/路径/排除文件混入）。
4. **README 重写**：面向贡献者（构建步骤、书源格式说明、调试参数、自检套件、合规文档链接），去个人化表述。
5. **CI 落地**：`gh auth refresh -s workflow` 后放回 `.github/workflows/`，加「开源边界检查」job。
6. **隐私/合规文档随仓库公开**：`docs/COMPLIANCE.md` 已就位。
7. **版本号/图标**：确认无商标冲突（「指尖阅读」名称与栖阅/轻悦无冲突；App 图标为原创生成）。

### 开源后的预期收益
- 书源生态共建（用户可 PR 书源兼容修复，如「书山聚合」这类真实源回归）
- 社区补 Android/多语言/测试
- 建立可信度：完整可审计的本地阅读器（对比 origo-x 的「裁剪版」更有吸引力）

## 5. 建议下一步（若决定开源）

1. 我先生成 **`PUBLIC_SOURCE_SCOPE.md` + `tool/check_public_source.py`**（仿 origo-x 机制）
2. 清理个人路径/敏感文件，重写 README 为贡献者向
3. 选定 License（需你拍板：AGPL-3.0 vs Apache-2.0）
4. 你 `gh auth refresh -s workflow` 后 CI 落地并设为公开仓库

## 附：两个仓库关键信息

- **origo-x**：Flutter 3.44.4 / Dart，AGPL-3.0-only；iOS RunnerTests 存在；`PUBLIC_SOURCE_SCOPE.md` 明确定义「本地版」边界；官方 Releases 可能有额外功能（与源码不同步）。
- **qysg**：仓库主体是 README + 5 个 HTML 模板（default/sb/bh/hy/tts，共约 2.9k 行）+ FlutterJSBridge 桥协议说明；描述 WebView 书源、正文图片 json（js/headers/imageDecode/段评图）、TTS 模板；无完整 App 源码树，许可未标注。
