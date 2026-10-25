# 主题系统 v2 优化方案（借鉴 origo-x / 栖阅）

## 现状（指尖阅读当前）

| 层 | 现状 |
|---|---|
| App 主题 | `ZJPalette` 5 套固定配色（青白/月白/雾蓝/暖沙/暗墨）+ 随配色图标 |
| 阅读主题 | `ReaderTheme` 3 套（米宣纸/深墨/护眼绿）+ `ReaderThemePreset` 主题包（.zjtheme）+ 背景图（ReaderBackgroundStore） |
| 分离度 | ✅ 阅读画布独立于 App 主题（与 origo-x 理念一致） |

## 借鉴点

### 来自 origo-x
1. **阅读主题 = 独立调色板**（ReaderThemePalette）：background/text/secondary/surface/controlBar/controlFill/accent/onAccent/border/shadow + 背景图+透明度 —— 指尖目前 ReaderTheme 只有 4 色，缺「控制栏/边框/阴影」等阅读器 chrome 色。
2. **自定义主题页 + 主题顺序存储**（reader_custom_themes_page + ReaderThemeOrderStore）：可新建/排序/启停。
3. **App 主题 = 单一强调色生成**（ColorScheme.fromSeed + 18 色快捷 + 色盘/hex）—— 指尖 App 主题是整组固定色，不够灵活。

### 来自栖阅
4. **AppTheme 54 字段 + ReaderTheme 37 字段**：卡片背景/封面/启动图/卡片背景/进度条跟随等。
5. **深色/浅色独立主题 + 跟随系统**（appTheme 有 separateDark/followSystem + 深浅绑定）。

### 来自 qysg
6. **正文图片 json 扩展**（js/headers/imageDecode/段评图）—— 属功能非主题，暂不纳入。

## 方案（分 3 步，每步独立可交付）

### 阶段一：阅读主题 v2（本轮落地）
- **内置扩到 6 套**：米宣纸 / 深墨 / 护眼绿 / 羊皮纸（暖调）/ 暗夜青（OLED 蓝青）/ 素白（极简）。
- **阅读 chrome 配色**：给 ReaderTheme 增加 `surface/controlBar/accentOn`（控制栏、边框用），与正文分离。
- **自定义主题编辑器**：从当前阅读设置创建、编辑 5 色（背景/正文/次级/强调/chrome）、hex 输入 + 快速色板、背景图关联（复用 ReaderBackgroundStore）、深/浅独立保存。
- **主题顺序/启停**：可排序、可停用内置（origo 思路），持久化到 `reader_theme_meta.json`。

### 阶段二：App 强调色任意色盘
- 保留 5 套整组配色（一键场景），新增「强调色」入口：18 色快捷 + 自定义 hex + 色盘（ColorPicker）。
- 强调色仅覆盖 `ZJ.accent/accentPressed` 及选中态；背景/文字仍走所选整组（origo 的 seed 思路，但不整组重算，降低回归风险）。

### 阶段三（后续，可选项）
- `.red`/`.qibubble` 已支持；补 `.qitheme` 风格外部包映射（含 chrome/背景）。
- 阅读背景图深色独立配置（现在只有单图）。

## 风险与取舍
- 阶段一改动集中在 ReaderTheme + 阅读设置页 + ReaderTextBuilder（chrome 色注入控制栏），阅读正文渲染路径不变 → 低风险。
- 阶段二只改 accent 令牌，全局即时生效，风险极低。
- 不做「整组色由 seed 生成」（Material3 fromSeed）——会改变现有 5 套精心调好的配色，回归成本高；改用「整组 + 可调强调色」混合。

## 验收
- 6 套内置可切换、chrome 色随主题变化；自定义主题创建/编辑/导入导出可用；
- 强调色任意选择即时生效且可回退；自检追加主题断言。
