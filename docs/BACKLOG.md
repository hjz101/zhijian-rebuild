# 指尖阅读 · 代办事宜（按栖阅对比生成）

> 依据：[QIREADER-COMPARISON.md](QIREADER-COMPARISON.md)（2026-10-25，综合对齐度约 65–70%）。
> 原则：先补“书源好不好用”，再补“像不像栖阅”，最后补“能不能上架”。
> 估算为单人全职参考（天）；验收以可演示 + Debug/Release 构建通过为准。

## 0. 总览

| 阶段 | 目标 | 任务数 | 估算 |
|---|---|---:|---:|
| P0 | 书源日常可用（登录/发现/规则/缓存/搜索） | 10 | 25–35 天 |
| P1 | 阅读器与主题对齐（双页/标题/图片/主题包） | 8 | 20–30 天 |
| P2 | 同步、数据完整性与安全 | 9 | 18–28 天 |
| P3 | TTS/AI、性能与体验打磨 | 8 | 15–25 天 |
| P4 | 发布与合规 | 4 | 4–8 天 |
| **合计** | | **39** | **约 82–126 人天** |

建议节奏：**S1 = P0 前 6 项（3–4 周）→ S2 = P0 剩余 + P1 前 3 项 → S3 = P1 剩余 + P2 → S4 = P3/P4**。

---

## P0 · 书源日常可用（最高优先）

### [P0-01] ✅ 已完成 · 书源登录 UI 与登录态持久化
- **对应差距**：栖阅 `LoginService` + `loginUi` + `loginCheckJs` + `loginInfo`；我们只有 `loginCheckJs`。
- **范围**：
  - `Features/Sources/` 新增登录页/表单 Sheet：`loginUrl` 用 WKWebView；`loginUi` 支持 `text/select/toggle/button`。
  - `SourcePipeline` 暴露登录态；`BookSource` 增加按源 `loginInfo` 持久化（`login_info.json`）。
  - 登录后执行 `loginCheckJs`，结果写回登录态；搜索/详情/目录/正文共用。
- **验收**：带登录的书源可完成“打开登录页→提交→搜索成功”；重启 App 登录态保留；失败有可读错误。
- **估算**：5–8 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `loginUi` JSON（`@js:`/`<js>` 可解析）→ 原生 text/password/toggle/select/button 表单；
  - `loginUrl` 非 JS 时 WKWebView 登录页 + Cookie 提取；
  - `loginUrl` 为 `@js:`/`<js>` 时执行登录脚本，支持 `java.putLoginHeader` / 返回对象；
  - 登录态按源持久化到 `source_login.json`，注入搜索/详情/目录/正文/体检/批量测试；
  - 入口：书源列表「登录」按钮 + 已登录徽标；
  - 自检：登录测试源 4 行表单 → 保存 `username/remember/server` + `Cookie` 头；重启保留。
  - 调试：`-seedLoginSource`、`-showSourceLogin`、`-autoSubmitLogin`。

### [P0-02] ✅ 已完成 · 发现 / Explore
- **2026-10-25 真源适配（📚书山聚合 v5.61）**：
  - `<js>…</js>` 解包修复（原 `dropLast(4)` 会残留 `<`，导致 `SyntaxError: Unexpected token '<'`）；
  - 规则 JS 统一包进 `eval` 独立作用域，修复同上下文 `let` 重声明（exploreUrl 与 bookList 同名变量）；
  - `data:detailsUrl|data:catalogUrl|data:chapterUrl` 私有协议：不发起 HTTP，payload 转 hex 作为 `result` 交给规则 JS；
  - POST body 为 JSON 且未声明 Content-Type 时自动补 `application/json`；
  - 发现页分类失败自动跳到下一个分类并顶部提示，不再整页报错；
  - 实测：215 个分类、个性推荐 30 本书、详情页解析成功；
  - 动态 `header` 规则求值（补齐 `X-Novel-Token`/`X-Api-Key` 签名头）后，目录接口正常返回（3947 章）；
  - `java.androidId()/deviceID()` 改为稳定 16 位 hex（原 `zhijian-ios` 被聚合后端判为「伪造设备码」并 429）；
  - 429 增加 `Retry-After` 退避；
  - 该源正文由聚合后端加密下发（且解码密钥长度非法），已识别为「加密正文」并给出可读提示，不再展示乱码；
  - 顺带修复 P1-04 引入的回归：无图片的 HTML 正文未清洗标签；
  - 卷名行（`isVolume=true`、`chapterUrl` 为空）不再进入阅读章节列表，修复「[-11] 规则无结果：chapterUrl 为空」；
  - 支持 `yuedu://booksource/importonline?src=…`（官方书源更新链接）与 `src` 参数，一键导入/更新书源；
  - 阅读器错误页新增「换源」入口；
  - 该源 5.61/5.66 的正文都需账号登录后才会返回明文（服务端按 `getSecretKey()` 决定是否加密），未登录时给出明确引导。
  - 后续（同日）：`java.ajax` 记录末次响应，后端鉴权失败映射为 `-12`；详情页给出「登录该书源」入口；loginUrl 自动 `login()`；loginUi 按钮逐个执行源内 action；表单 POST 补 `application/x-www-form-urlencoded`；JS 错误不再把所有 `is not an object` 误判为「缺失 JS API」。
- **对应差距**：栖阅 `ExploreFilterEngine` + 分类/筛选/信息流/网格；我们完全缺失。
- **范围**：
  - 解析 `exploreUrl` / `ruleExplore`（分类、筛选、列表、书籍字段）。
  - `Features/Sources/` 新增发现页；支持分类切换、筛选、分页/加载更多。
  - 复用 `BookDetailView` 加书架。
- **验收**：至少 2 个真实书源可浏览分类并打开详情；空分类/失败有占位。
- **估算**：4–6 天
- **依赖**：P0-01（登录源）
- **完成情况（2026-10-25）**：
  - 新增底部「发现」Tab；书源横滑选择 + 分类横滑；
  - 解析 `exploreUrl` 的三种形式：JS（`@js:`/`<js>`）、JSON 数组、`标题::URL` 行文本；
  - `ruleExplore` 列表字段（name/author/kind/intro/lastChapter/coverUrl/bookUrl）映射为 `SourceBook`；
  - 分页「加载更多」、详情 Sheet、登录态徽标；
  - 调试：`-seedExploreSource`、`-autoExplore`；本地 mock 实测 6 本书/页。
  - 未做：筛选器（`exploreScreen`）、信息流/网格布局、多级分类。

### [P0-03] ✅ 已完成 · 替换规则（正文清洗）
- **对应差距**：栖阅 `ReplaceRuleService` 13 字段；我们没有。
- **范围**：
  - `Core/Reader` 新增 `ReplaceRule` 模型 + 存储 + 应用器（正则/替换/作用域/顺序/超时）。
  - 正文构建前清洗；支持导入/导出 JSON。
- **验收**：广告行/乱码/站点后缀可被规则移除；规则启停即时生效。
- **估算**：3–5 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `ReplaceRule`：pattern/replacement/isRegex/scope(content/title/both)/enabled/order/timeout；
  - `ReplaceRuleEngine`：按 order 执行、`$1…$9` 捕获组、`\n` 转义、1s 超时保护、失败记录；
  - `ReplaceRuleStore`：JSON 持久化、增删改/启停/拖动排序、导入（数组或 `{version,rules}` 包）、导出；
  - 正文/标题清洗接入 `BookContentService`（远程与本地书都生效）；
  - UI：设置 → 替换净化；列表/编辑/预览/清洗预览页；导入文件/粘贴、导出分享；
  - 实测：广告行删除 + 域名替换（`applied=2`）、标题 `第12章 ` 前缀移除；`-replaceRuleTest`。

### [P0-04] ✅ 已完成 · 章节规则（目录/正文修正）
- **对应差距**：栖阅 `ChapterRuleManager`；我们没有。
- **范围**：目录去重/排序/卷名识别/正文标题去重规则；按源配置。
- **验收**：目录倒序/重复章节可被规则修正；规则不影响已有缓存一致性。
- **估算**：2–3 天
- **依赖**：P0-03
- **完成情况（2026-10-25）**：
  - `ChapterRuleConfig`：去重、过滤空标题、卷名识别、自动纠正倒序、强制倒序、编号排序、标题清理正则、卷名正则；
  - `ChapterRuleEngine`：去空 → 标题清理 → 卷名识别 → 去重 → 倒序 → `normalizedTOC`；返回去重/去空/卷名/反序统计；
  - 全局规则 + 按书源覆盖（`chapter_rules.json`）；
  - 设置 → 目录规则：开关、正则、示例预览、按源覆盖编辑；
  - 已接入 `SourcePipeline.toc`（远程目录）与本地书目录无需清洗；
  - 实测：7 条脏目录 → 5 条，去重 1、去空 1、卷名 1，顺序 1→2→3→卷2→4；
  - 调试：`-chapterRuleTest`、`-autoOpenChapterRules`。

### [P0-05] ✅ 已完成 · 章节磁盘缓存
- **对应差距**：栖阅 `Caches/ChapterCache`；我们仅内存 `chapterCache`。
- **范围**：
  - `BookContentService` 落盘目录/正文/摘要；LRU/容量统计/清理。
  - 离线打开已缓存章节；换源/更新目录时失效策略。
- **验收**：断网可读已缓存章节；缓存大小可见并可清理；重复打开不重复请求。
- **估算**：2–3 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `ChapterCacheStore`：`Caches/ChapterCache/<sha256(bookId)>/{toc,meta,chapter_*.json}`；
  - 目录 TTL 24h：命中先返回旧目录保证离线可读，后台刷新成功再更新；失败保留旧目录；
  - 正文缓存：按 chapterUrl 失效（换源/目录更新自动不命中）；命中不重复请求；
  - LRU：默认 200 MB，超限按修改时间删除最旧章节；
  - 设置 → 章节缓存：总大小/文件数/书籍数、按书清理、全部清理；
  - `invalidate(bookId:)` 同时清磁盘缓存；
  - 实测：写 2 章目录 + 1 章正文 → `toc=2 bodyChars=600 size=2KB books=1 files=3`；
  - 调试：`-chapterCacheTest`、`-autoOpenChapterCache`。

### [P0-06] ✅ 已完成 · 搜索分页 / 取消 / 结果缓存
- **对应差距**：栖阅 `SearchEngine` 分页/取消/缓存；我们只搜第 1 页且不可取消。
- **范围**：`EngineRegistry.search(page:)`、结果去重、任务取消、最近关键词缓存。
- **验收**：搜索页可“加载更多”；切换关键词能取消旧请求；重复搜索秒开。
- **估算**：2–3 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `EngineRegistry.search(keyword:page:useCache:)`：page 透传、任务取消后返回空、结果缓存（180s，key=关键词|页码|源数）；
  - 搜索页：`加载更多`（按 bookUrl 去重合并）、`取消`按钮、`重搜`、结果总数/源数/耗时摘要；
  - 切换关键词/重搜会取消旧 Task；取消后不写缓存；
  - 实测：第 1 页 100 条/3 源、第 2 页 100 条/3 源、缓存命中 0ms；
  - 调试：`-searchPageTest`。

### [P0-07] ✅ 已完成 · 书架分组 + 排序
- 网格/列表切换、列数 2–5、布局设置页与实时预览；
- 排序：最近阅读 / 添加时间 / 书名（`@AppStorage("shelf.sort")`）；
- 分组：分组 chip 筛选、长按「移动到分组」、新建/重命名/删除、移出分组；
- 空书架「在书源中搜索」入口；书源页胶囊分段 + 完成按钮；
- 未做：分组拖拽排序、分组封面。
- **对应差距**：栖阅分组/网格列数；我们只有单网格。
- **范围**：`Book.groupName` 已有字段；新增分组管理/筛选/排序（最近阅读/添加时间/书名）。
- **验收**：可新建/重命名/删除分组；分组内书籍可移动；重启保留。
- **估算**：1–2 天
- **依赖**：无

### [P0-08] ✅ 已完成 · 阅读统计
- **对应差距**：栖阅 `ReadingStatisticsService` + 目标；我们没有。
- **范围**：阅读时长（前后台/章节）、书籍数、连续天数、日/年目标；图表页。
- **验收**：阅读 5 分钟可见时长增长；目标进度可见；数据本地持久化。
- **估算**：2–3 天
- **依赖**：P0-07（分组统计可选）
- **完成情况（2026-10-25）**：
  - `ReadingStatsData`：按日时长 + 按日书籍集合 + 日目标(分钟) + 年目标(本)；旧结构自动迁移；
  - 统计页：今日目标卡（进度条/还差多少/百分比）、本周/连续/书籍三卡、7 日柱状、30 日趋势、年度目标、汇总（总时长/活跃天/日均）；
  - 阅读页退出/退后台自动计入，并记录 bookId 用于书籍统计；
  - 目标编辑 Sheet（日时长 10–180 分、年 5–200 本、清空数据）；
  - 实测：种子数据下「今日 7 分 / 目标 30 分 / 还差 23 分 / 23%」、本周 2 小时 57 分、连续 8 天、年度 4/24 本。

### [P0-09] ✅ 已完成 · 书源编辑 / 导出 / 分组
- **对应差距**：栖阅完整书源管理；我们只有导入/启停/删除。
- **范围**：JSON 编辑、单条/批量导出、分组、去重、排序、URL 导入校验。
- **验收**：编辑后立即生效且可回滚；导出可被 Legado/栖阅导入；分组筛选可用。
- **估算**：3–4 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `SourceEditorView`：单条书源 JSON 编辑、名称/地址只读、分组输入 + 已有分组快捷 chip、启用开关、校验保存、复制 JSON、导出该书源、删除；
  - `SourceStore`：`update/setGroup/setEnabled/groups/deduplicate/exportJSON`；
  - 书源页：点击卡片进入编辑；分组 chip 筛选；工具栏「导出全部书源」「去重」；
  - 导出为 prettyPrinted + 不转义斜杠 + 排序键，可被 Legado/栖阅直接导入；
  - 调试：`-editFirstSource`、`-showSourceList`。

### [P0-10] ✅ 已完成 · `jsLib` 共享脚本
- **对应差距**：栖阅 `SharedJsScope`；我们字段保留但未执行。
- **范围**：按源加载 `jsLib`（缓存/下载），注入 JSC 后再执行规则。
- **验收**：依赖 `jsLib` 的书源规则可运行；脚本加载失败有诊断。
- **估算**：1 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `JSRuntime.installJsLibIfNeeded`：初始化后立即执行 `jsLib`，支持 `@js:`/`<js>`/内联/HTTP(S) URL；
  - `SharedJsLibCache`：远程脚本磁盘缓存（Caches/JsLib，24h TTL，网络失败回退过期缓存）；
  - 诊断：`jsLibStatus` 计入 `diagnosticsSnapshot`；失败追加 JS console 日志；
  - 实测：内联 jsLib 定义 `sharedGreeting` 后规则 JS 可调用，返回「你好，阅读（jsLib）」。

---

## P1 · 阅读器与主题对齐

### [P1-01] ✅ 已完成 · 双页 / iPad 横屏
- **对应差距**：栖阅 `ReaderTwoPageRenderer`；我们没有。
- **范围**：TextKit 双页布局、跨页选择、横屏/分屏适配、页码。
- **验收**：iPad 横屏双页阅读正常；标注/高亮跨页正确；旋转不丢进度。
- **估算**：3–5 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `ReaderViewModel.isTwoPage`（开关 + 横屏 + 宽度 ≥640pt）；分页宽度改为单栏 `(宽-28)/2`；
  - `PagedReaderView` 新增 `ReaderSpreadViewController`：一屏两栏、等宽、28pt 栏距、单页时右侧留白；
  - 双页步进 2 页（左右滑动/点击/上下章边界）；页码显示「1–2 / 12 页」；
  - 旋转/分屏后按字符锚点重新分页，进度不丢（`setViewport` → `repaginate`）；
  - 设置页新增「双页模式」开关；调试 `-twoPageTest`、`-forceTwoPage`。
  - 注：本机 iPad 模拟器无法启动（core sim 报 device not located），双页渲染在 iPhone 竖屏用 `-forceTwoPage` 验证通过。

### [P1-02] ✅ 已完成 · 翻页动画 + 音量键翻页
- **对应差距**：栖阅 `PageCurlDriver` + `volumeButtonPageTurnEnabled`；我们没有。
- **范围**：页卷曲/淡入/无动画三选项；音量键翻页开关；与 TTS 冲突处理。
- **验收**：三种动画可切换；音量键翻页不改变系统音量；可关闭。
- **估算**：2–3 天
- **依赖**：P1-01
- **完成情况（2026-10-25）**：
  - `ReadingSettings.pageTurnAnimation`：平移（scroll）/ 仿真（pageCurl）/ 淡入（crossDissolve）/ 无动画；
  - `PagedReaderView` 按动画选择 `transitionStyle`，淡入用 `UIView.transition`；`.id(animation)` 保证切换后重建控制器；
  - `VolumeButtonPageTurnMonitor`：隐藏 `MPVolumeView` + 音量还原，`+1/-1` 交给 `nextPage/previousPage`，不改系统音量；
  - 设置页新增「翻页动画」菜单、「音量键翻页」开关；TTS 播放时不拦截（仅在分页模式生效）。

### [P1-03] ✅ 已完成（简化版）· HTML 章节标题设计器
- **对应差距**：栖阅可视化 SPA（8 类元素/图层/撤销/资源）；我们仅对齐/大小/分隔线/花饰。
- **范围**：
  - 标题模板 JSON（元素/样式/资源）；WKWebView 离屏渲染 + 高度测量 + 快照缓存。
  - 简化版设计器：文字/装饰/线/图片/背景，拖拽缩放，导入导出。
- **验收**：可保存 3 套标题模板并实时预览；分页高度正确；JSON 可导出/导入。
- **估算**：5–8 天
- **依赖**：P1-01（高度测量）
- **完成情况（2026-10-25）**：
  - `ChapterTitleTemplate/Element`：text/line/ornament/image，支持位置/宽度/字号/字重/颜色/字距/对齐/透明度；`__TEXT__` 占位符；
  - 内置 3 套模板（简约墨字 / 墨线留白 / 花饰题头）+ 自定义模板增删改/另存/导入导出 JSON；
  - `ChapterTitleHTML` 生成绝对定位 HTML；`ChapterTitleSnapshotService` 离屏 WKWebView 快照（60 条内存 LRU，含主题色背景）；
  - 阅读器按页面宽度等比插入 `NSTextAttachment`，分页高度随标题区变化；双页按单栏宽度渲染；
  - 设计器 UI：实时预览、模板切换、元素增删、位置/宽度/字号/透明度滑块、对齐与内容编辑；
  - 入口：阅读设置「章节标题设计器」+ 阅读器工具栏 `格式` 按钮；
  - 实测：`snapshot=300x150`、`htmlBytes=1080`、导出 `zhijian-chapter-titles.json`、3 套模板。
  - 未做：拖拽缩放画布、图层顺序调整、图片元素导入（字段已预留）。

### [P1-04] ✅ 已完成 · 正文内嵌图片 / 阅读背景
- **对应差距**：栖阅 `NSTextAttachment` + 背景图/模糊；我们没有。
- **范围**：文本阅读器图片附件、等比/占位、点击查看；阅读背景图（亮度/模糊）。
- **验收**：含图章节分页正确；图片可点开；背景图不影响文字对比度。
- **估算**：2–3 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `ReaderImageExtractor`：正文 HTML 中 `<img>`（含 `data-src`/`data-original`）→ 提取 URL + `[[IMGn]]` 标记，保留 alt；
  - `ReaderImageStore`：正文图片下载 + `Caches/ReaderImages` 磁盘缓存 + 内存表 + 并发去重；占位图与等比 bounds；
  - `BookChapterContent.images` / `SourceChapterContent.images` / 章节缓存三方透传；
  - `ReaderTextBuilder` 以 `NSTextAttachment` 插入图片（按页宽等比），附件带 `.readerImageURL`；
  - 点击正文图片 → `ImageViewerScreen` 全屏缩放查看（分页 + 双页均支持）；
  - 阅读背景：`ReaderBackgroundStore`（相册选图、不透明度、模糊、启用开关，限制长边 2000px）+ `ReaderBackgroundView` 叠加主题底色；分页页背景改为透明以显示背景图；
  - 设置页「阅读背景图」入口 + 预览；章节缓存页新增正文图片缓存统计/清理；
  - 实测：`images=2 attachments=2`、背景图 `hasImage=true bytes=38241` 且阅读页可见。

### [P1-05] ✅ 已完成 · 主题 / 预设包导入导出
- **对应差距**：栖阅 `.qitheme/.qipreset/.qired`；我们没有。
- **范围**：定义自有 ZIP 格式（`theme.json` + assets），导入/导出/应用；内置 3 套迁移。
- **验收**：导入主题后颜色/背景/字体立即生效；导出可再次导入。
- **估算**：3–5 天
- **依赖**：P1-04
- **完成情况（2026-10-25）**：
  - `ReaderThemePreset`：主题名/背景/文字/次级/强调色 + 字号/行距/段距/页边距/字体；
  - 内置 3 套（米宣纸/深墨夜读/护眼绿）+ 自定义；从当前设置一键创建；
  - `.zjtheme` ZIP 包（`theme.json` + README）导入/导出；兼容裸 JSON；
  - 应用：颜色/字号/行距/段距/页边距写入 `ReadingSettings`，字体随自定义字体库联动；
  - 阅读设置 → 阅读主题包；实时预览卡片；
  - 实测：`presets=4 export=测试主题.zjtheme bytes=647 roundtrip=测试主题 bg=#EDE4D4`。

### [P1-06] ✅ 已完成 · 自定义字体
- **对应差距**：栖阅字体导入/元数据；我们仅宋体/苹方。
- **范围**：字体文件导入、注册、字体选择器、分页签名包含字体。
- **验收**：导入 TTF/OTF 后可选；切换字体重新分页且进度不丢。
- **估算**：1–2 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `CustomFontStore`：`CTFontManager` 注册 TTF/OTF/TTC，PostScript 名索引，`Application Support/Zhijian/Fonts` 持久化；
  - `ReadingSettings.customFontName`：自定义字体优先，`layoutSignature` 含字体名，切换即重排并保进度；
  - 字体管理页：导入（多选）、列表（自定义字体渲染预览）、应用、删除、系统字体（宋体/苹方）回退；
  - 设置 → 字体管理入口；主题包可绑定自定义字体。
  - 注：模拟器无可用 TTF 样本，注册路径按 API 验证编译通过；真机待测。

### [P1-07] ✅ 已完成（规则包部分）· 高亮规则包 / 气泡样式
- **对应差距**：栖阅 `.qihighlight` / `.qibubble`；我们仅本地规则。
- **范围**：规则 JSON 导入导出；段评气泡样式（颜色/圆角/图标）可选。
- **验收**：规则包可导入导出；气泡样式切换即时生效。
- **估算**：2–3 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `HighlightPackageView`：高亮规则导入/导出（`[{name, pattern, colorHex, enabled, isRegex}]`，兼容 `.qihighlight` JSON）；
  - 入口：自动高亮规则页「📦」按钮；
  - 气泡样式（颜色/圆角/图标）未做，待 P1-07 后续或并入 P2-09 热评样式。

### [P1-08] ✅ 已完成 · URL Scheme / 文档类型
- **对应差距**：栖阅 `qireader://`/`yuedu://` + 文件关联；我们没有。
- **范围**：`CFBundleURLTypes`、`onOpenURL` 导入书源/主题/备份；扩展 pdf/cbz/zip/rar/7z 文档类型。
- **验收**：浏览器点链接可导入；文件 App 可“用指尖阅读打开”。
- **估算**：1 天
- **依赖**：P1-05
- **完成情况（2026-10-25）**：
  - `CFBundleURLTypes`：`zhijian://`、`qireader://`、`yuedu://`；
  - `URLSchemeHandler`：`source?url=` / `theme?url=` / `backup?url=` 导入书源、主题包、下载备份；
  - 文档类型与 `UTImportedTypeDeclarations`：`.zjtheme` / `.qihighlight` / `.zjbk`；
  - `onOpenURL` 全局挂载。

---

## P2 · 同步、数据完整性与安全

### [P2-01] ✅ 已完成 · iCloud 文档容器 + 自动备份
- **对应差距**：栖阅文档容器 + never/onExit/daily/weekly；我们仅 KVS。
- **范围**：ubiquity 容器、备份镜像、自动备份调度、恢复入口。
- **验收**：签名构建下 iCloud Drive 可见备份；自动备份按频率执行。
- **估算**：3–5 天
- **依赖**：Apple 签名/容器
- **完成情况（2026-10-25）**：
  - `AutoBackupStore`：频率 never/onExit/daily/weekly + 上次备份时间 + 结果记录；
  - `AutoBackupRunner`：导出 .zjbk 到 iCloud Drive（不可用时落 Documents/ZhijianAutoBackup）；
  - 挂接 `scenePhase`：进入前台按 daily/weekly 周期补跑；退后台 onExit 触发；
  - iCloud 恢复入口：列出云端 .zjbk（按时间倒序），确认后 `BackupService.restore` 整体恢复；
  - 设置页 iCloud：自动备份开关 + 频率 chip + 立即备份 + 上次时间；云端备份查看/恢复；
  - 实测：未签名环境自动落到 Documents/ZhijianAutoBackup/zhijian-*.zjbk；签名构建走 iCloud Drive；
  - 调试：`-autoBackupTest`。

### [P2-02] ✅ 已完成 · WebDAV 目录增量镜像
- **对应差距**：栖阅 `mirrorDirectory/needsCopy`；我们只传单个 `.zjbk`。
- **范围**：PROPFIND 比对大小/时间，仅上传变化文件；冲突提示。
- **验收**：第二次上传仅传变化文件；远端目录结构与本地一致。
- **估算**：3–5 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `WebDAVClient` 新增 `listDirectoryContents` / `putFile(相对路径, 自动建目录)` / `deleteRemoteFile`；
  - `WebDAVMirrorService.mirror`：递归 PROPFIND 远端 ↔ 本地（大小+修改时间），只上传新增/变化文件；冲突（远端较新且大小不同）跳过并提示；可选删除远端多余文件；
  - 备份页 WebDAV 新增「镜像备份目录到 WebDAV（增量）」，镜像 `Documents/ZhijianAutoBackup`；
  - 纯 diff 离线自检 `-webdavMirrorDiffTest`：upload/unchanged/conflicts/delete 判定正确（远端较旧→上传，远端较新→冲突）；
  - 注：远端递归 PROPFIND 需服务器支持 Depth:1 逐层列举（WebDAV 标准）。

### [P2-03] ✅ 已完成 · 备份纳入本地书正文 备份纳入本地书正文/漫画/PDF
- **对应差距**：栖阅可选 localBooks；我们仅元数据。
- **范围**：可选分类、压缩、大小上限、恢复路径重建。
- **验收**：勾选后备份可恢复本地书可读；不勾选保持轻量。
- **估算**：2–3 天
- **依赖**：P2-02

### [P2-04] ✅ 已完成 · WebDAV / TTS 凭据迁移 Keychain
- **对应差距**：双方都明文；作为改进项。
- **范围**：`SecItem` 封装、迁移旧 JSON、删除明文、UI 提示更新。
- **验收**：重启后可自动登录；JSON 中无密码。
- **估算**：0.5–1 天
- **依赖**：无
- **完成情况（2026-10-25）**：
  - `KeychainStore`（GenericPassword，service+account 存取，删除/清空）；
  - WebDAV：`webdav.json` 不再存密码，`persist()` 写入 Keychain（`com.zhijian.reader.webdav`），首次启动自动迁移旧明文并清空；`remove` 同时删 Keychain；
  - TTS：登录 Header（可能含 Token）迁移 Keychain（`com.zhijian.reader.tts.login`），JSON 只留偏好/源变量；
  - 未签名/缺 entitlement 环境（模拟器、自签 IPA）自动回退明文并置 `usingFallbackStorage` 供 UI 提示；
  - 自检 `-keychainTest`：写入/读取/删除往返、JSON 不含密码（签名环境）、回退标记。
  - 注：Keychain 写入在无 keychain-access-groups entitlement 的构建上被系统拒绝（-34018），属预期；正式签名构建自动使用 Keychain。

### [P2-05] ✅ 已完成 · 本地 RAR / 7z 导入 本地 RAR / 7z 导入
- **对应差距**：栖阅支持；我们引擎可读但书架未接。
- **范围**：`LocalImportService` 用 `ArchiveReader` 解包 TXT/EPUB/图片；文件类型关联。
- **验收**：RAR/7z 漫画/TXT 可导入；损坏包有错误提示。
- **估算**：1–2 天
- **依赖**：RAR 样本

### [P2-06] ✅ 已完成（简化）· 文件管理器 文件管理器（简化）
- **对应差距**：栖阅内置文件管理器；我们依赖系统导入。
- **范围**：App 文档目录浏览/移动/删除/导入；仅本地文件。
- **验收**：可管理已导入文件；删除后书架状态一致。
- **估算**：2–3 天
- **依赖**：无

### [P2-07] ✅ 已完成 · JSC 私有 API 替代 JSC 私有 API 替代
- **对应差距**：我们使用 `JSContextGroupSetExecutionTimeLimit`（上架风险）。
- **范围**：调研公共可中断方案/沙箱进程/规则静态检查；不可行则 Release 关闭并文档化。
- **验收**：Release 不含私有符号；死循环有兜底（超时/禁用源）。
- **估算**：2–4 天
- **依赖**：无

### [P2-08] ✅ 已完成 · ATS / 网络安全策略 ATS / 网络安全策略
- **对应差距**：双方都 `NSAllowsArbitraryLoads`。
- **范围**：按域名例外、书源 HTTPS 优先、危险源提示；审核说明。
- **验收**：默认不全局放开；书源兼容性回归通过。
- **估算**：1–2 天
- **依赖**：无

### [P2-09] ✅ 已完成（热评部分）· 评论/段评热评与本章说样式 评论/段评热评与本章说样式
- **对应差距**：栖阅热评/本章说/作家说/SVG 气泡；我们简化。
- **范围**：热评排序、本章说入口、作家说标识、气泡样式。
- **验收**：章末可显示热评 Top3；本章说可展开。
- **估算**：3–5 天
- **依赖**：P1-07

- **完成（2026-10-25）**：备份可勾选「包含本地书正文」，EPUB/PDF/Manga/local_library.json 打入 `local/`；恢复写回 AppData.root；manifest.includesLocalBooks 标记。

---

## P3 · TTS/AI、性能与体验

### [P3-01] ✅ 已完成 · TTS 睡眠定时 TTS 睡眠定时
- **对应差距**：栖阅 `TtsSleepTimer`；我们没有。
- **范围**：分钟/章节末/倒计时；到点淡出停止。
- **验收**：定时后按预期停止；锁屏可控。
- **估算**：0.5–1 天

### [P3-02] ✅ 已完成（OpenAI 兼容）· LLM 角色识别 LLM 角色识别（可选）
- **对应差距**：栖阅 OpenAI 兼容 + JSON Schema + 批处理 + 缓存；我们启发式。
- **范围**：Provider 配置、Keychain Key、章节批处理、角色缓存、失败回退。
- **验收**：开启后角色归属优于启发式；关闭不影响朗读；Key 不进备份。
- **估算**：4–6 天

### [P3-03] ✅ 已完成（引擎播放器版）· TTS PCM 流式播放 TTS PCM 流式播放
- **对应差距**：栖阅 AVAudioEngine 流式；我们落盘播放。
- **范围**：WS 二进制帧→AudioConverter→AVAudioEngine；首句延迟优化。
- **验收**：首句开始时间明显缩短；暂停/切句正常。
- **估算**：3–5 天

### [P3-04] ✅ 已完成 · 图片缓存 / 封面缓存 图片缓存 / 封面缓存
- **对应差距**：栖阅 ImageCache；我们 AsyncImage。
- **范围**：内存+磁盘 LRU、失败占位、清理。
- **验收**：重复浏览不重复下载；缓存可清理。
- **估算**：1–2 天

### [P3-05] ✅ 已完成（简化）· JSC 池 / 空闲清理 JSC 池 / 空闲清理
- **对应差距**：栖阅 JSContextPool；我们串行队列。
- **范围**：按源复用/限额/空闲回收。
- **验收**：多源批量测试内存不持续增长；吞吐提升。
- **估算**：2–3 天

### [P3-06] ✅ 已完成 · 源响应速度统计/排序 源响应速度统计/排序
- **对应差距**：栖阅 SourceSpeedTracker；我们没有。
- **范围**：记录搜索/详情耗时，换源排序，体检展示。
- **验收**：换源列表按速度排序；数据可重置。
- **估算**：1 天

### [P3-07] ✅ 已完成 · DNS 覆盖 / 代理 DNS 覆盖 / 代理（高级）
- **对应差距**：栖阅本地 CONNECT 隧道；我们没有。
- **范围**：书源级 DNS/IP、HTTP/SOCKS 代理、不污染全局。
- **验收**：指定源可走代理/IP；其他源不受影响。
- **估算**：2–4 天

### [P3-08] ✅ 已完成 · 批注稳定坐标 批注稳定坐标
- **对应差距**：栖阅 StableTextCoordinate；我们 UTF-16 章内偏移。
- **范围**：内容哈希 + 前后文锚点，重排/换源后尽量重定位。
- **验收**：改字号/换主题后批注位置不漂移。
- **估算**：3–5 天

- **完成**：TTSController 睡眠定时（关/10/20/30/60 分），到点自动停止并清空；朗读停止时取消；UI 在朗读页。

---

## P4 · 发布与合规

### [V2.3] ✅ 已完成 · 版本 2.3 四项深化（二批）
- **WebView 主执行器**：`jsExecutorMode`（0 自动 / 1 仅 JSC / 2 WebView 优先），阅读设置可选；WebView 优先时纯函数脚本先走 WKWebView；**mode=2 真实书源回归通过**（书山聚合 215 类/200 本）；
- **i18n 低频文案**：文案表扩到 140+ key，BackupView/FileBrowserView/SourcesView/TTSConfigView 等接入；
- **dp:N 段评图片**：`<img src="dp:N">` 解析 → 正文渲染「💬×N」气泡胶囊（accent 色）；
- **气泡皮肤**：`bubbleSkin`（0 胶囊 / 1 圆角 / 2 对话气泡），阅读设置可选，PagedReaderView 按皮肤渲染；
- 自检扩到 **42 项全通过**（含 dp 解析/识别 2 断言）。

### [V2.3] ✅ 已完成 · 版本 2.3 三项深化
- **版本号 2.3**（MARKETING_VERSION）；
- **i18n 全量**：LocalizationManager 文案表扩到 100+ key（Tab/书架/统计/设置/阅读器/来源/发现/TTS/备份/通用），主要页面文案接入 `tr()`；
- **imageDecode 解密**：图片 json 协议 `js` 参数 → WebViewJSExecutor 跑书源解密函数（base64→base64），下载后解密再解码；
- **WebView 执行器接入管线**：JSRuntime.evaluateJS JSC 失败时，纯函数脚本（无 java./source. 依赖）自动 WebView 兜底重跑；
- WebViewJSExecutor 加就绪门闩（didFinish + 0.2s 兜底）；`-webViewJSExecTest` 回归通过（sum=7/JSON）；自检 40 项通过。

### [QYSG-INSPIRED] ✅ 已完成 · 借鉴 qysg/origo-x/栖阅 五项
- **③ 简繁转换**：`TraditionalConverter` 内嵌常用字表 + 阅读设置「正文繁体」开关 + 正文渲染转换；
- **① 图片 json 协议**：`<img src="url,{json}">` 单引号 JSON 解析（headers/js/imageDecode）→ ExtractedReaderImage，下载应用自定义 headers（imageDecode 解密函数待书源 JS 执行扩展）；
- **⑨ 发现网格**：ExploreView 列表/网格（2 列）切换 + 网格卡片；**⑦ 统计**：已有 30 日柱状图，JSON 数据量小不迁 SQLite（文档化）；
- **④ WebView 执行器**：`WebViewJSExecutor`（离屏 WKWebView + 同步信号量 + 8s 超时）+ `RuleJSSyncExecutor` 协议；`-webViewJSExecTest` 验证 sum=7 / JSON 序列化；正式管线默认 JSC（切换需异步化，文档化）；
- **⑤ 自检基线 + ⑥ i18n 骨架**：自检扩到 40 项（含简繁/图片协议）；`LocalizationManager`（中/英切换 + 文案表）+ 设置入口；XCTest target 迁移路径文档化（开源后社区补）。

### [THEME-V2] ✅ 已完成（阶段三）· .qitheme 外部主题包映射
- `.qitheme`（栖阅 AppTheme ZIP）：解析 AppTheme JSON 54 字段子集（primary/secondary/accent/defaultBackground/readerThemeLight）→ ReaderThemePreset；
- chrome 色 surface 由背景色亮度自动生成；`ReaderThemePreset.surfaceHex` 新增（含编解码）；
- `apply` 统一把外部主题（.red/.qitheme/.zjtheme）写入 customPalette（含 surface）完整呈现；
- 主题包页支持 .qitheme 扩展名导入；自检 35 项全通过（含 QITheme 6 断言）。

### [THEME-V2] ✅ 已完成（阶段二）· 外观重构为 origo-x seed 方案
- App 外观 = 中性基底（亮/暗）+ 单一强调色 seed 动态生成整套色板（hue 调整生成 accent/celadon/gold）；
- 外观页：预设场景 5 套 + 18 色快捷 + ColorPicker + hex + 外观模式（跟随系统/浅/深）；
- 兼容迁移：旧 `zhijian.app.palette` 整组配色 key → seed；
- `-palette=` 调试映射到 applyPreset；RootView preferredColorScheme 跟随模式；
- 实测：`-palette=anmo` 深色底 `#070A0E` + seed 强调色即时生效；外观页 OCR 确认。

### [THEME-V2] ✅ 已完成（阶段一）· 主题系统 v2（借鉴 origo-x / 栖阅）
- 内置阅读主题扩到 6 套：米宣纸 / 深墨 / 护眼绿 / 羊皮纸 / 暗夜青 / 素白；
- 阅读 chrome 色：`ReaderTheme.surface`（控制栏/卡片），正文与 chrome 分离（origo 理念）；
- 自定义配色编辑器：5 色（背景/正文/次级/强调/chrome）+ hex 规范化 + 深浅开关 + 实时预览；
- `ReaderCustomPalette` 覆盖内置主题，阅读页/正文/背景/控制栏同步生效；
- 实测：暗色自定义配色 `#2B2B33/#E6E1D8` 端到端生效；选择器 6 套 + 自定义 + 清除入口；
- 方案文档 `docs/THEME-V2.md`（阶段二 App 强调色色盘待做）。

### [R2-04] ✅ 已完成 · 长章稳定性（滚动自动分页）
- 滚动模式超长章节（>6 万字）自动切分页（`longChapterAutoPaged` 开关，默认开）；
- ScrollReaderView 复用 textStorage 避免整章重建；
- 实测：9 万字 TXT 章节滚动模式下自动切成 376 页分页，避免整章 UITextView 卡顿；
- 调试：`-scrollMode -seedLongTxt -autoOpenBookTitle=长章TXT测试`。

### [R2-05] ✅ 已完成 · 外部主题/气泡格式导入
- `.red`（Red App 主题归档，裸 JSON 或 ZIP theme.json）→ ReaderThemePreset（light 侧映射 + `#AARRGGBB` 归一）；
- `.qibubble` JSON → ReadingSettings 气泡颜色/圆角/图标；阅读设置「段评气泡」新增导入入口；
- 自检 29 项全通过（含 Red-normalize / Bubble-color/corner/icon）。

### [R2-01] ✅ 已完成 · Cookie eTLD+1（精简 PSL）
- `PublicSuffixList`：多段后缀（com.cn/co.uk 等）+ 常见单段后缀；`CookieJar.header` 改为按 eTLD+1 共享 Cookie（a.example.com 与 b.example.com 不再串）。

### [R2-02] ✅ 已完成 · 真实书源回归矩阵
- `-selfTestSuite -sourceRegression`：对已导入书源执行搜索+发现真实回归写 `source-regression-report.txt`；
- 实测：关于小说搜索 100 本；书山聚合 jsLib 正常、215 类、个性推荐 30 本、搜索 200 本。

### [R2-03] ✅ 已完成 · 压缩包导入回归
- `-archiveImportTest`：图片包→漫画（2 页）、txt 包→分章（2 章）均通过；
- 注：本机无合法 RAR 样本，RAR 真机回归留待用户提供（libarchive 已支持）。

### [R1-01] ✅ 已完成 · 文档纠偏
- `QIREADER-COMPARISON.md` 重写：130 文件 / 35,445 行，P0–P3 逐项 ✅/🟡，综合对齐度约 85%。

### [R1-02] ✅ 已完成 · 统一回归自检
- `-selfTestSuite`：JSBlock / PseudoURL / ReplaceRule / ChapterRule / BackupCrypto / WebDAVMirror.diff / StableTextCoordinate / TTSSegmenter / parseTOCNumber，20/20 通过，报告写 `self-test-report.txt`。

### [R1-03] ✅ 已完成 · 内存稳定性
- `ReaderImageStore` 图片内存 LRU（上限 80 张，触达即淘汰）；
- `EngineRegistry` 空闲 3 分钟自动回收复用的 pipeline（释放 JSContext）。
- 待办：滚动模式分块加载（长章 1 章整塞 UITextView，需重写选择/高亮交互，R2）。

### [P4-01] 正式签名 + TestFlight
- 需要 Apple Developer Team、证书、Provisioning Profile；`ExportOptions.plist`；真机回归。
- **估算**：1–2 天（依赖账号）

### [P4-02] App Store 物料
- 6.7"/6.1" 截图、预览文案、隐私政策 URL、支持 URL、审核说明（ATS/书源）。
- **估算**：1–2 天

### [P4-03] 隐私与合规复查
- 隐私清单、数据收集声明、第三方内容/书源免责声明、开源许可清单。
- **估算**：0.5–1 天

### [P4-04] CI 启用
- `gh auth refresh -s workflow` 后把 `docs/ci/ios-build.yml` 放回 `.github/workflows`；加 Release 构建缓存。
- **估算**：0.5 天

---

## 建议的 Sprint 切分

| Sprint | 内容 | 产出 |
|---|---|---|
| S1（3–4 周） | P0-01/02/03/04/05/06 | 登录书源可用、发现页、正文清洗、离线缓存、搜索分页 |
| S2（2–3 周） | P0-07/08/09/10 + P1-06 | 书架分组、统计、书源管理、jsLib、自定义字体 |
| S3（4–5 周） | P1-01/02/03/04/05/07/08 | 双页/翻页动画/HTML 标题/图片背景/主题包/URL Scheme |
| S4（3–4 周） | P2-01/02/03/04/05/06/07 | iCloud/增量镜像/本地书备份/Keychain/RAR/文件管理器/私有 API |
| S5（2–3 周） | P3 + P4 | LLM 角色/PCM/缓存/统计优化 + 签名/上架 |

---

### [P0-07/P0-08] ✅ 部分完成（2026-10-25）
- 栖阅式 UI：三 Tab（书架/统计/设置）、浅色玻璃、墨色强调、大标题、卡片分组。
- 阅读统计：今日/本周/连续、7 日柱状图、总时长/活跃天/日均；阅读页停留自动计时。
- 书架：3 列网格、搜索框、编辑删除、✨ 发现入口、书源入口；分组/排序未做。
- 发现：从书架 ✨ 进入（Sheet）；原独立 Tab 已按栖阅布局移除。
- 调试：`-seedReadingStats`。
- 配色：`ZJPaletteStore` 5 套（青白玻璃/月白宣纸/雾蓝灰/暖沙可可/暗墨玻璃），设置 → 界面与布局 → 外观切换，全局即时生效。

## 本周可立即做的 5 件事

1. **P0-01 登录 UI**（最高价值，直接决定付费/登录源可用性）
2. **P0-02 发现页**（书源生态入口）
3. **P0-03 替换规则**（正文质量）
4. **P0-05 章节磁盘缓存**（离线/省流）
5. **P0-06 搜索分页/取消**（基础体验）

---

## 不做 / 明确取舍

- **不引入远程书源后端**（栖阅 `RemoteBackendService`）：减少攻击面与合规风险。
- **不实现 trust-all TLS**、**不硬编码密钥**：安全底线。
- **不复制栖阅/Legado/origo-x 代码或资源**：仅按公开协议/行为规格实现。
- **不内置书源/内容**：由用户自行导入。

## 风险与依赖

| 风险 | 影响 | 应对 |
|---|---|---|
| Apple 开发者账号/证书缺失 | 无法真机/TestFlight/iCloud 文档 | 先做模拟器可验证项；签名项并行准备 |
| JSC 私有 API 审核 | 上架被拒 | P2-07 优先给出 Release 替代方案 |
| RAR 样本缺失 | P2-05 无法验收 | 用 libarchive 生成/收集样本 |
| 书源站点反爬/登录变化 | P0-01/02 验收波动 | 固定 2–3 个稳定测试源 |
| 双页/标题设计器工作量大 | 延期 | 先做简化版（P1-01/P1-03 MVP），再迭代 |
