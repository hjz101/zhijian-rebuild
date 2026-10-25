# GitHub 仓库说明

## 目录归类

| 路径 | 内容 |
|---|---|
| `Zhijian/App` | 入口、RootView、AppEnvironment 依赖容器 |
| `Zhijian/Core/Models` | Legado 书源模型、书/章节、阅读设置、TTS/WebDAV/备份 |
| `Zhijian/Core/Pipeline` | 四阶段书源流水线（search/bookInfo/toc/content） |
| `Zhijian/Core/Runtime` | JSRuntime、packages_stub / jsoup 桥、Codec、Headless WebView、libarchive |
| `Zhijian/Core/Reader` | TextKit 分页、EPUB/PDF/漫画内容、批注/评论存储 |
| `Zhijian/Core/TTS` | 系统/HTTP TTS、多角色、WebSocket |
| `Zhijian/Core/Sync` | .zjbk 备份、加密、WebDAV、iCloud KVS |
| `Zhijian/Features` | SwiftUI 页面（书架/书源/阅读/设置/TTS/备份） |
| `Zhijian/Resources` | 内置示例书源、示例 EPUB/PDF/CBZ、JS 兼容层 |
| `docs` | 重建状态、引擎/阅读/TTS 笔记、发布/GitHub 说明 |
| `docs/screenshots` | README 引用的少量关键截图（完整开发截图不纳入仓库） |
| `dist` | 本地未签名 IPA（已 gitignore，通过 Release 附件分发） |

## 构建

```bash
xcodebuild -project Zhijian.xcodeproj -scheme Zhijian \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/zj build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

CI：`docs/ci/ios-build.yml`（GitHub Actions macos-15 模拟器构建）。
当前 OAuth token 缺少 `workflow` scope，先未放入 `.github/workflows`；获得权限后执行：

```bash
gh auth refresh -s workflow
mkdir -p .github/workflows
cp docs/ci/ios-build.yml .github/workflows/ios-build.yml
git add .github/workflows/ios-build.yml
git commit -m "ci: enable iOS build workflow"
git push
```

## 首次上传

```bash
cd zhijian-rebuild
gh auth login                 # 选择 GitHub.com，完成浏览器授权
gh repo create zhijian-rebuild --private --source . --remote origin --push
```

若仓库已在网页端创建：

```bash
git remote add origin https://github.com/<user>/zhijian-rebuild.git
git push -u origin main
```

## 仓库约定

- 不提交 `dist/`（未签名 IPA）与 `shots/`（开发过程截图），产物走 GitHub Releases。
- 示例书源/示例书仅用于本地调试，正式发布前请替换或移除。
- 本工程为独立重建实现：QiReader 仅作为行为规格参考，未复制其源码/资源；复用部分来自作者自己的旧工程。
