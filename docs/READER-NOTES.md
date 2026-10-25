# 阅读器分线（Reader）说明 — P0 分页阅读器

> 分线范围：`Zhijian/Core/Reader/**`、`Zhijian/Features/Reader/**`、本文件。
> 共享契约（`AppEnvironment`、`AppModels`、`ReaderContracts`、`SourcePipeline`）未改动；共享模型新增字段需求：无。

## 1. 入口

```swift
ReaderScreen(book: Book)   // Features/Reader/ReaderScreen.swift
```

- 由书架（Lead）以 `NavigationLink` / `fullScreenCover` / `sheet` 调起；需要环境中存在 `AppEnvironment`（`@EnvironmentObject`，RootView 已注入）。
- 初始化后自动创建 `ReaderViewModel`，拉目录 → 正文 → 分页。
- 关闭时 `persistNow()` 立即写回进度并 `env.tts.stop()`。

## 2. 文件结构

| 文件 | 职责 |
|---|---|
| `Core/Reader/BookContentService.swift` | `ReaderContentProviding` 实现：远程书源四阶段流水线 + `LocalLibrary` 本地书 |
| `Core/Reader/ReaderTextBuilder.swift` | 章节标题/正文 → `NSAttributedString`（字体、行距、段距、首行缩进、标题去重） |
| `Core/Reader/PaginationEngine.swift` | TextKit 断页 + 线程安全缓存（后台串行队列） |
| `Core/Reader/ReaderViewModel.swift` | `@MainActor @Observable` 状态机：目录/正文/翻页/预取/进度/TTS |
| `Features/Reader/PagedReaderView.swift` | `UIViewControllerRepresentable` + `UIPageViewController` 单页渲染、滑动/点击、章间过渡页 |
| `Features/Reader/ScrollReaderView.swift` | 滚动模式整章 `UITextView` + 比例上报 |
| `Features/Reader/ReaderScreen.swift` | `ReaderScreen(book:)` 入口、纸面背景、玻璃顶栏、页码、加载/错误层 |
| `Features/Reader/ReaderSheets.swift` | 目录 Sheet（搜索/当前章定位）与设置 Sheet（主题/字体/字号/行距/段距/页边距/模式/页码） |

## 3. 内容服务

### 远程书

1. `book.sourceUrl` → `env.sources.sources` 里匹配 `BookSource`（找不到给明确错误）；
2. 构造 `SourceBook(name/author/bookUrl/sourceUrl…)`；
3. `SourcePipeline.bookInfo → toc → content`，映射为 `[Chapter]` / `BookChapterContent`；
4. 目录成功后顺手更新 `BookStore` 的 `totalChapters / lastChapter`。

并发约定：`SourcePipeline` 内部有 `currentBook/currentChapter/vars` 状态，**每次阶段调用新建 pipeline**，
Cookie 通过 `initialCookies` + `onCookiesChanged` 在本服务内跨调用延续，避免并发串状态。
`bookInfo` 结果按 `book.id` 缓存，`content` 阶段直接传入，少请求一次详情页。

### 本地书（Lead 的 `LocalLibrary`）

- `book.isLocal == true`：按 `book.id` 取 `LocalLibrary.shared.record(for:)`；
  - `chapters`：`record.chapters` → `[Chapter]`；
  - `content`：按 `Chapter.index` 取 `LocalChapterRecord.text`；
- 记录缺失/章节缺失/目录为空均抛 `ReaderContentError`（`LocalizedError`），UI 直接展示。
- 离线示例书 `demo-local-001`《山居书简》可完整走通分页/翻页/进度/TTS 链路。

## 4. 分页引擎（TextKit）

- 一章一个 `NSTextStorage` + `NSLayoutManager`；每页创建一个高度=正文可用高度的 `NSTextContainer`，
  逐个 `glyphRange(for:)` 取本页字形范围，再映射成 UTF-16 字符范围 `ReaderPage{index, range}`。
- 页面容器宽高 = SwiftUI `GeometryReader` 计算的正文区域（去掉页边距与顶部/底部留白），
  与 `UIPageViewController` 中 `UITextView` 的 `textContainer`（inset=0、lineFragmentPadding=0）一致。
- 断页在专用串行队列完成，结果回到主线程；`PaginationEngine` 为 `@unchecked Sendable`，缓存有锁。

### 缓存

- Key：`(bookId, chapterIndex, layoutSignature, width, height, contentHash)`。
- `layoutSignature` 只含 `fontFamily / fontSize / lineHeight / paragraphSpacing`（颜色与断页无关）；
  `width/height` 半像素取整；`contentHash` 防正文变化后命中旧页。
- LRU-FIFO 上限 160 条；`invalidate(bookId:)` / `invalidate()` 可手动清。
- 主题切换只重建 `NSAttributedString`（颜色），不重新断页；字号/行距/段距/旋转触发重排，
  重排后用当前页起始字符偏移定位到新页，避免阅读位置跳变。

## 5. 交互

- 左右滑动：`UIPageViewController`（`.scroll` 转场）。
- 点击左 1/3：上一页（章首再点进入上一章末页）；点击右 1/3：下一页（章末再点进入下一章首页）；
  点击中间 1/3：显隐玻璃控制层。
- 章首/章尾额外一页"上一章/下一章"过渡页：继续滑动或点击过渡页跨章；跨章加载中显示顶部 pill，
  加载失败保留原章节并弹出错误层（重试/返回）。
- 顶栏：返回 / 目录 / 设置 / TTS；副标题显示 `第 x/y 章 · 章节名 · 进度%`。
- 底部页码：分页模式 `第 x / y 页 · 进度%`；滚动模式 `第 x / y 章 · 进度%`。
- 设置 Sheet 直接改 `env.settings.settings`（`SettingsStore`），通过 Combine 同步到 ViewModel：
  主题/字号/行距/段距/页边距实时生效；分页↔滚动切换即时切渲染器。
- 目录 Sheet：章节列表、搜索、当前章高亮 + 自动滚动定位。

## 6. 进度与 TTS

- 进度写回：`env.books.markRead(book.id, chapter: page: ratio:)`，页变化/换章后 600ms 防抖，
  退出时 `persistNow()` 立即写。`ratio = (chapterIndex + 章节内进度) / 章节总数`。
- 恢复：启动时用 `book.currentChapterIndex` / `currentPageIndex`（滚动模式用 `currentScrollRatio`）定位。
- 预取：当前章渲染完成后延迟 350ms 预取下一章正文，放入正文缓存（最多 12 章，超过清空）。
- TTS：`env.tts.speak(当前页纯文本)` / `env.tts.stop()`；滚动模式无页概念时读整章文本。

## 7. 已知缺口（P0 范围内）

1. **无文本选择/划线/笔记/书签/换源/本地导入**：正文 `UITextView` 关闭了选择与交互，仅做渲染。
2. **分页为单章**：跨章通过"过渡页 + 重新加载"实现，不是跨章无缝滑动的整书窗口化分页。
3. **滚动模式是简单整章 UITextView**：无窗口化虚拟滚动、无跨章自动接续（需顶栏/跨章入口）。
4. **图片/富媒体占位**：正文按纯文本排版（`SourcePipeline` 已输出清洗后纯文本），暂无图片附件。
5. **TTS 当前页高亮/句子跳转**：依赖 TTS 分线提供回调；当前仅调用 `speak/stop` 读当页。
6. **主题仅三套内置**（paper/ink/moss）；无自定义背景图/字体导入。
7. **页大小变化时**（旋转/分屏）会重排并尽量保持页首字符位置；同一字符跨页偏移的极端情况可能落在页首 ±1 页。
8. **本地书内容变更**（重新导入同名 bookId）不会主动清分页缓存；依赖 `contentHash` 自动失效，
   但正文缓存（`contentCache`）在本 ViewModel 生命周期内不会感知外部重导入。
9. 目录分页/单章超长（>8192 页）时截断，防死循环。

## 8. 与其他分线的接口

- 依赖 Lead：`AppEnvironment` 的 `books/sources/settings/content/tts`、`LocalLibrary.shared`、`ReaderScreen(book:)` 入口挂接书架。
- 当前书架 `ShelfView` 仍用临时 `ReaderPlaceholder`；把 `.sheet(item: $opening)` 的内容替换为
  `ReaderScreen(book: book)` 即完成接线（Reader 分线未改书架文件）。
- 不改 `SourcePipeline` / `ReaderContracts`；未新增共享模型字段。
- `BookContentService` 仍是 `AppEnvironment` 里 `content` 的具体类型，初始化签名未变。

## 9. 验证记录

- 编译：`xcodebuild -project Zhijian.xcodeproj -scheme Zhijian -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/zj-reader build` → **BUILD SUCCEEDED**（含其他分线最终状态）。
- 模拟器（iPhone 17 / iOS 26.5，本地示例书 `demo-local-001`）走通：
  分页首章/章间翻页到第 2 章、标题与首行缩进、米宣纸/深墨主题实时切换、字号 20→24 实时重排、
  分页→滚动切换、目录 Sheet 当前章高亮、设置 Sheet 联动。
- 视觉验证截图（临时产物，不入库）：`/tmp/zj-reader-page1b.png`（米宣纸分页）、
  `/tmp/zj-reader-ch2-ink.png`（深墨 24pt 跨章）、`/tmp/zj-reader-scroll.png`（滚动）、
  `/tmp/zj-reader-settings.png`、`/tmp/zj-reader-catalog.png`。
