# PHASE 5A — iOS 打通(Enablement)

> **定位**:Phase 5 的**前置打通**,不是 Phase 5 本体。目标是让 iOS 端「能日常用」——能打开、能编辑、能保存、能记住上次的库——**不追求外壳美观**。外壳设计属 Phase 5 本体(见下方整体顺序)。

## 整体顺序(为什么叫 5A)

本阶段处在一个三段推进的第一段:

1. **Phase 5A — iOS 打通到能日常用**(本文档):修 KI-1 导航、文件夹 bookmark 持久化、确保开/编/存可用。**不追求好看,最小改动。**
2. **回 macOS 打磨核心(editor.html 的债)**:math 块三路入口、undo 边界。每一项定稿前先在 iOS 上过一遍再确认。
3. **Phase 5 本体 — iOS 外壳设计**:侧栏形态、快速记录、搜索优先界面。

这个顺序决定了 5A 的一条纪律:**5A 的所有修法都保持最小,凡涉及侧栏/外壳形态的"正规解"一律留给 Phase 5 本体**,现在不过度投入、不预先定型,以免 Phase 5 返工。

## 现状核实(2026-07-26,只读)

**两端当前完全不持久化工作目录**——这是「新建」而非「改造」:

- `AppState.init`(`Models/AppState.swift:72-99`)只恢复 theme + zoom,无 workingDirectory 恢复。
- UserDefaults 全仓仅 4 处,均为主题/缩放(`selectedThemeId`/`editorZoomLevel`),无目录键。
- `workingDirectory`(`Models/AppState.swift:48`)`didSet` 只加载文件、不写持久化;5 个赋值点全是即时选择(NSOpenPanel / documentsURL)。
- `recentFiles`(`Models/AppState.swift:7`)纯内存,从不写盘。
- `bookmark`/`securityScope`/`startAccessing` 全仓 0 命中。

**沙盒确认**:两个 build config 均 `ENABLE_APP_SANDBOX = YES` + `ENABLE_USER_SELECTED_FILES = readwrite`(`Inkwell.xcodeproj/project.pbxproj`)。故 **macOS 与 iOS 都必须走 security-scoped bookmark + `startAccessing`/`stopAccessing` 配对**,两端同款纪律。

## 一、KI-1 导航修复(方案 A,过渡方案)

**问题**:iPhone compact 宽度下点文件不翻页到编辑器(详见 `KNOWN_ISSUES.md` KI-1)。

**修法(方案 A)**:compact 宽度下打开文件时把 `columnVisibility` 切到 `.detailOnly`,把 detail 列翻到前台;回文件列表复用现有侧栏 toggle。只影响 iPhone compact,regular(iPad/macOS)不变。

> **⚠️ 过渡性质(必须留痕)**:方案 A 是 **Phase 5A 的最小可用修法**,不是侧栏导航的最终形态。侧栏导航的正规形态(是否改用 `NavigationSplitView` 管理的 `List(selection:)`,让系统在 compact 下自动 push/pop)**留待 Phase 5 本体的 iOS 外壳设计一并决定,届时重新评估**。
>
> 落地时须在**两处**注明此过渡性质:①`columnVisibility` 切换处的**代码注释**;②`KNOWN_ISSUES.md` 的 **KI-1 条目**。目的:避免日后看到那段 `columnVisibility` 操作时误以为它是深思熟虑的最终形态。

## 二、文件夹 bookmark 持久化(全量跨平台,新建)

让用户选中一个**本地可访问目录**并跨启动记住它。

### 存储
- UserDefaults 存一份 bookmark `Data`(+ 显示名,供失败提示文案用)。
- iOS:普通 security-scoped bookmark(`url.bookmarkData()`,URL 来自 picker,已带安全作用域)。
- macOS:`url.bookmarkData(options: .withSecurityScope, ...)`。
- 平台差异用 `#if os(...)` 封进一个小 helper。

### 入口
- **iOS**:`openFolder()` 从"硬编码 `documentsURL`"换成 `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`(不拷贝)。选中 → 拿到 security-scoped URL → 建 bookmark → 持久化。
- **macOS**:保留 `NSOpenPanel`(canChooseDirectories);选完后同样建 + 存 security-scoped bookmark。(给一个原本零持久化的入口**加**持久化,非叠加第二套。)

### 启动恢复
`AppState.init`(或早期时机)解析 bookmark → `startAccessingSecurityScopedResource()` → 成功则设 `workingDirectory`。

- **`isStale`**:在 access 活跃期间**重建 bookmark 并覆写存储**(静默自愈)。
- **解析 / access 失败**:**不静默变空侧栏**;显式给出**区别于 KI-1 表象**的提示(如 "Couldn't reopen '<名>' — it may have moved. Open a folder to continue."),并用现有 Open Folder 入口引导重选。**绝不让"记忆失效"退化成"列表空/点了没反应",以免与 KI-1 混淆。**

### 安全作用域配对纪律(硬约束)
- 全程只保持**一个**活跃 security-scoped URL:当前 `workingDirectory` 的根。
- 用一个属性持有"当前正在 access 的 URL"。切换目录时**先 `stopAccessing` 旧的,再 `startAccessing` 新的**。
- 退出时 `stopAccessing`(复用 macOS 已有的 `willTerminate` 观察者,见 save-flush 一轮)。
- `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` **必须严格配对**,否则泄漏 sandbox extension。配对约定写成代码注释,类比项目已有的闭包捕获纪律(见 `MarkdownEditorView` 的 WeakScriptMessageHandler 注释)。

### 明确不做(属 Phase 5「云盘支持」独立议题)
本轮只"选中一个本地可访问目录并记住它"。**不做**:
- 不接 `NSFileCoordinator`
- 不检查 `ubiquitousItemDownloadingStatus`
- 不处理未下载的占位符文件
- 不做外部变更检测 / 冲突检测

以上属「云盘支持」,是 Phase 5 的独立设计议题,不在 5A 预留结构、不预先选定方案。

## 三、提交拆分(每步在 iOS 上验证过再提交)

1. **docs**:本设计文档定稿(`PHASE_5A_IOS_ENABLEMENT.md`)。
2. **feat**:KI-1 导航(方案 A)+ 两处过渡性质注明(代码注释 + KNOWN_ISSUES KI-1)。iPhone compact 模拟器验证。
3. **feat**:bookmark 持久化 + iOS 文件夹选择器 + 启动恢复 + `isStale` 自愈 + 失败重选。iOS + macOS 双端验证。

> 编/存已可用(save-flush 于 2026-07-26 落地,commit `8c185ea` / `888a0b2`;编辑本就可用),故 5A 的实质增量集中在 KI-1 与 bookmark 两块。

## 四、实施记录(Implementation Log)

> 实施与设计不符、或踩到的坑,如实记录于此。差异本身有价值。

### KI-1(2026-07-28,commit `4a81637`)

- **`columnVisibility` 只管 regular,compact 要用 `preferredCompactColumn`**。最初按设计写 `columnVisibility = .detailOnly` 想在 compact 下翻到编辑器——**实测无效,仍停在侧栏**。根因:`NavigationSplitView` 在 compact 宽度下只显示一列,由 **`preferredCompactColumn`** 绑定决定显示哪列;`columnVisibility` **仅作用于 regular 宽度**。改用 `preferredCompactColumn = .detail` 后生效,返回侧栏由系统自带的返回按钮(‹)完成。**这是个会重复踩的坑**——Phase 5 重设计 iOS 侧栏导航时必然再次相关,记此备忘。
- **hook 从 `selectedFile` 移到 `activeTabId`(覆盖面的实质改进,非单纯位置调整)**。最初挂在 `ContentView` 的 `selectedFile` onChange,只覆盖"点已有文件"。但侧栏底部 "+" 新建走 `appState.createNewFile → openFile`(设 `activeTabId`),**不经过 `selectedFile`**——那样在 compact 下新建文件不翻页。改挂 `activeTabId` onChange(点已有文件与新建最终都改 `activeTabId`),一次覆盖两条打开路径。
- **验证**:iPhone 17 / iOS 26.4(compact)——点已有文件翻页 ✅、"+"新建翻页 ✅、系统返回按钮回列表 ✅。regular 宽度不受影响(`preferredCompactColumn` 按 API 只作用 compact;macOS 编译+运行正常)。iPad 窗口化模拟器出现启动黑屏未能取得干净截图,单独记为 `KNOWN_ISSUES.md` KI-3(未定性)。
