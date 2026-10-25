# 指尖阅读 2.1 发布准备

## 构建信息

| 项 | 值 |
|---|---|
| 版本 | 2.1 (Build 2) |
| Bundle ID | `com.zhijian.reader` |
| 最低系统 | iOS 17.0 |
| 架构 | arm64 |
| 签名 | 未签名（`CODE_SIGNING_ALLOWED=NO`） |
| 归档 | `/tmp/Zhijian.xcarchive`（本机临时路径） |
| 未签名 IPA | `dist/Zhijian-2.1-unsigned.ipa` |
| 隐私清单 | `Zhijian/PrivacyInfo.xcprivacy`（已随包） |
| App Icon | `Assets.xcassets/AppIcon.appiconset/icon-1024.png` |
| 启动屏 | `UILaunchScreen` + `LaunchBackground` / `LaunchLogo` |

## 构建 / 归档命令

```bash
# Debug（模拟器）
xcodebuild -project Zhijian.xcodeproj -scheme Zhijian \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/zj-final build

# Release（真机，未签名）
xcodebuild -project Zhijian.xcodeproj -scheme Zhijian \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/zj-final-release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

# Archive（未签名，已实测成功）
xcodebuild -project Zhijian.xcodeproj -scheme Zhijian \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath /tmp/Zhijian.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## 正式签名步骤

1. Xcode 打开工程 → Signing & Capabilities，选择 Team。
2. 将 `PRODUCT_BUNDLE_IDENTIFIER` 改为自己 App ID（当前 `com.zhijian.reader`）。
3. 为 iCloud 能力创建容器（如 `iCloud.com.zhijian.reader`），同步修改：
   - `Zhijian.entitlements` 的 `icloud-container-identifiers`
   - `Info.plist` 的 `NSUbiquitousContainers`
   - `CloudSyncService.driveDirectory()` 的容器标识（当前使用默认容器）
4. `xcodebuild archive` 后 `-exportArchive` 导出 App Store 包。

## 提交前检查清单

- [x] App Icon 1024 无透明通道、无圆角
- [x] 启动屏（LaunchBackground + LaunchLogo，支持深色）
- [x] 版本号 2.1 (2)
- [x] 隐私清单 `PrivacyInfo.xcprivacy`（无跟踪、无收集、UserDefaults/文件时间戳原因）
- [x] 仅竖屏（iPhone）
- [x] `ITSAppUsesNonExemptEncryption = false`
- [x] 文档 / 关于页版本号
- [ ] 正式签名 + iCloud 容器实测
- [ ] App Store 截图（6.7"/6.1"）
- [ ] 隐私政策 URL / 支持 URL

## 已知发布风险

1. **JSC 超时私有 API**：`JSContextGroupSetExecutionTimeLimit` 通过 dlsym 调用，属 JavaScriptCore 私有接口。App Store 静态扫描有被拒风险；若无法接受，需在 Release 关闭该功能或改为可中断的脚本沙箱。
2. **iCloud Drive**：未签名构建不可用；签名后需验证容器与实际同步。
3. **WebDAV 密码明文**：`webdav.json` 未使用 Keychain，已在 UI 提示。
4. **ATS 任意加载**：为书源兼容开启 `NSAllowsArbitraryLoads`，审核需说明理由（阅读器需访问用户书源站点）。
5. **RAR**：libarchive 路径已通，但未构造真实 RAR 样本回归。
6. **WebSocket TTS**：协议约定为文本帧 + 二进制音频 + done，第三方源需自行适配。
7. **隐私问卷**：应用不收集数据；用户书源/Cookie/备份均在本地或用户自己的 WebDAV/iCloud。
