# 指尖阅读 · 已知限制与未完成项

> 诚实清单：让项目状态完全透明。标注「占位/骨架」的项是**刻意未做完整**，非隐藏缺陷。

## 功能占位/骨架
| 项 | 状态 | 说明 |
|---|---|---|
| 图片解密 `imageDecode` | ✅ 已完成 | 书源 `js` 解密函数经 WebViewJSExecutor（base64→base64） |
| WebView JS 执行器 | ✅ 已接入 | `jsExecutorMode`（自动/JSC/WebView 优先）+ JSC 失败自动兜底；真实源回归通过 |
| i18n 多语言 | ✅ 已完成 | 160+ key 中/英切换 + 审计报告（仅 1 处非 UI 文案未覆盖） |
| `.qitheme` 背景图 | ⚠️ 待补 | 颜色字段已映射；归档内背景图资源未提取（本轮补齐） |
| 阅读统计 | ✅ | JSON + Charts 面积图 + 热力图 + CSV 导出 |
| 段评图片 `dp:N` | ✅ 已完成 | `<img src="dp:N">` 渲染「💬×N」气泡 |
| Webtoon 漫画专项 | ✅ 已完成 | 默认滚动模式（LazyVStack 懒加载）+ 横屏双页 |
| SVG 气泡皮肤 | ✅ 已完成 | 胶囊/圆角/对话气泡 3 种皮肤 + `.qibubble` skin 字段 |
| `.qibubble/.red` 字段子集 | ⚠️ 部分 | 常用字段已映射；54 字段其余项（启动图/进度条）未映射（本轮评估） |

## 待真机/签名验证
| 项 | 说明 |
|---|---|
| PCM 流式播放 | 引擎在模拟器无渲染设备会阻塞；需真机验证 |
| Keychain | 未签名回退明文；真签名构建才真正用 Keychain |
| 音量键翻页 | 依赖 MPVolumeView，需真机 |
| 后台播放 | 需真机 + 后台模式 |

## 依赖外部资源
| 项 | 说明 |
|---|---|
| RAR 真实样本 | 本机无合法 .rar；libarchive 支持，未真实回归 |
| 更多书源 | 只实测书山聚合/关于小说；欢迎社区 PR 补充回归源 |

## 明确取舍
| 项 | 说明 |
|---|---|
| 远程后端 | 设计上不引入（无账号/无服务端，攻击面小） |
| 跨平台 | 仅 iOS（SwiftUI 原生）；或需另做 Android/Flutter |
| JSC 私有 API | Debug 用超时 API；Release 已禁用（上架安全） |
| ATS 任意加载 | 兼容用户 HTTP 书源；已提供 HTTPS 优先开关 + 审核说明 |

## 开源边界
- 完整清单见 `PUBLIC_SOURCE_SCOPE.md`；`tool/check_public_source.py` 自动检查通过
