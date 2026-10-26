# 指尖阅读 · 上架合规复查清单（R3-01）

> 目标：App Store 审核前逐项核对。标 ⚠️ 的项需要开发者在签名/上架时处理。

## A. 已就位（✅）

| 项 | 状态 | 说明 |
|---|---|---|
| 隐私清单 | ✅ | `PrivacyInfo.xcprivacy`：无跟踪、无收集数据、UserDefaults(CA92.1)/FileTimestamp(C617.1) 已声明 |
| 无硬编码密钥 | ✅ | 无内置 AES Key / Token / 密钥 |
| 无 trust-all TLS | ✅ | 无自定义 TLS 信任绕过 |
| 加密合规 | ✅ | `ITSAppUsesNonExemptEncryption=false`（仅标准 HTTPS + 本地 AES-GCM 备份，非出口管制） |
| 备份加密 | ✅ | PBKDF2-SHA256 120k + AES-GCM（用户口令，非预置密钥） |
| Keychain 凭据 | ✅ | WebDAV/TTS Key 存 Keychain；未签名环境回退明文并提示 |
| 书源内容 | ✅ | 应用不内置任何书源/内容；书源由用户导入（合规关键） |
| 本地导入 | ✅ | 内容均用户自备（TXT/EPUB/PDF/漫画） |

## B. 需注意（⚠️）

| 项 | 状态 | 说明 |
|---|---|---|
| **JSC 私有 API** | ⚠️ | Debug 用 dlsym `JSContextGroupSetExecutionTimeLimit`；**Release 已 `#if DEBUG` 禁用**，不链接私有符号。上架构建=Release，无风险；留档说明。 |
| **ATS 任意加载** | ⚠️ | `NSAllowsArbitraryLoads=true` 为兼容用户自导入 HTTP 书源。已提供「书源 HTTPS 优先」开关。**审核问询应答话术**：① 本 App 不包含任何自有网络请求的明文 HTTP——所有明文请求均来自用户主动导入的第三方书源规则；② 书源格式为开源 Legado 规范，HTTP 是第三方站点的既有协议，App 无法替站点升级 HTTPS；③ 已默认开启「HTTPS 优先」，仅在源不支持 HTTPS 时回退明文；④ 若审核强制要求，可改为 NSExceptionDomains 逐域放行或要求书源 HTTPS，但会显著降低书源兼容性。 |
| **WebDAV 明文回退** | ⚠️ | 未签名环境 Keychain 不可用时回退明文存 JSON（仅本机，含 UI 提示）。正式签名构建走 Keychain。 |
| **第三方内容版权** | ⚠️ | 书源/书库由用户导入，App 不提供聚合/下载入口。需在审核备注说明「BYO 书源/文件」模式。 |
| **WebSocket TTS** | ⚠️ | 自定义协议（二进制 PCM/文本帧），无内置服务端。 |
| **libarchive dlsym** | ⚠️ | `/usr/lib/libarchive.2.dylib` 弱链接读取 RAR/7z；dlsym 动态加载系统库，非私有 API（系统公开动态库），上架一般无碍；若被拒再改为内嵌解码器。 |

## C. 上架物料（P4-02 骨架）

- **App 名称**：指尖阅读（Zhijian）
- **副标题**：本地书源阅读器（自带书源/本地文件导入）
- **分类**：图书 / 效率
- **关键词**：小说, 书源, 阅读, EPUB, PDF, 漫画, TTS, 听书, 本地
- **隐私链接**：本 App 不收集任何数据（`NSPrivacyCollectedDataTypes` 为空），可在审核备注说明
- **截图脚本**：`-showExplore` / `-autoOpenBookTitle=` / `-tab=N` 已可用于生成商店截图
- **审核备注模板**：
  > 本 App 是一款本地阅读器：不包含任何预置内容或书源。用户自行导入书源 JSON（开源 Legado 格式）与本地文件（TXT/EPUB/PDF/CBZ）。为兼容用户自备的 HTTP 书源启用了任意 HTTP 加载，并默认 HTTPS 优先。登录信息与 WebDAV 凭据保存在 iOS Keychain。无账号体系、无广告、无内购、无数据收集。

## D. CI

- 工作流：`docs/ci/ios-build.yml`（push/PR 触发，macos-15 模拟器构建）
- 启用：`gh auth refresh -s workflow` 后把文件复制回 `.github/workflows/ios-build.yml` 并推送。
