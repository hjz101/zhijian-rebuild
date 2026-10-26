# 指尖阅读 Widget（集成说明）

> Widget 需要独立 extension target。为避免破坏主工程 pbxproj，源码放本目录，按下面步骤在 Xcode 集成（2 分钟）。

## 集成步骤（Xcode 26）

1. **新建 Widget Extension target**：File → New → Target → 搜「Widget Extension」→ 名称 `ZhijianWidget`
   - 勾选「Include Configuration App Intent」：**不勾**（用 StaticConfiguration）
2. **加入源码**：把本目录 `WidgetBundle.swift`、`WidgetSnapshot.swift` 拖入新 target 的 Sources
   - 删除模板自动生成的 `ZhijianWidgetBundle.swift` 里 @main 的重复定义（用我们的）
3. **配置 App Group**：
   - 宿主 target（Zhijian）Signing & Capabilities → + App Groups → `group.com.zhijian.reader`
   - Widget target 同样加 App Group（同一个）
   - 宿主 `Zhijian.entitlements` 已含 `com.apple.security.application-groups`（本轮已加）
4. **运行**：跑宿主 App → 长按主屏 → 添加「阅读进度」小组件

## 数据流
- 宿主 `ReaderViewModel.didDisplayPage` → `WidgetBridge.save`（App Group UserDefaults `widget.snapshot`）
- Widget `ReadingProvider` 读同一 key，15 分钟刷新一次

## 调试
- 宿主：`-widgetTest` 调试参数会写入示例快照
- 模拟器小组件：跑宿主 App 后，`xcrun simctl launch booted com.apple.Preferences` 添加即可
