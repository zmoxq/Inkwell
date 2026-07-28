# Inkwell 已知问题(Known Issues)

> 记录已确认、但当轮不修复的问题,供后续 Phase 统一处理。每条注明发现日期、根因、归属、候选方案。

---

## KI-1 · iPhone(compact 宽度)点击文件不翻页到编辑器

- **发现日期**:2026-07-26
- **平台**:iOS,仅 **iPhone(compact width)**;iPad / macOS(regular width)不受影响
- **状态**:Phase 5A 以**方案 A(过渡)**最小修复(见 `PHASE_5A_IOS_ENABLEMENT.md` §一);**正规导航形态留待 Phase 5 iOS 外壳设计重新评估**
- **归属**:预存在问题,非 save-flush 改动引入

### 现象

iPhone 上侧栏文件列表可见,点击某个 `.md` 文件后仍停留在侧栏,编辑器不出现,表现为「点了打不开」。

### 链路诊断

打开文件的**数据链路本身是通的**:

1. 点文件 → `TyporaFileRow.onTapGesture` 设 `selectedFile`(`Views/SidebarView.swift:428`)
2. `ContentView.onChange(of: selectedFile)` → `appState.openFile(url)`(`Views/ContentView.swift:52`)
3. `openFile` 建 tab、置 `activeTabId`,`currentDocument` 变为非 nil(`Models/AppState.swift:199`)
4. detail 区 `editorArea` 依据 `currentDocument` 渲染编辑器(`Views/ContentView.swift:114`)

**根因在布局层,不在 openFile 链路:**

- 外壳是 `NavigationSplitView`(`Views/ContentView.swift:42`),侧栏是自绘 `ScrollView` + `LazyVStack` + `onTapGesture`,**不是** `List(selection:)`。
- `NavigationSplitView` 在 compact 宽度下一次只显示一列,系统只在**侧栏的 `List(selection:)` 变化**时才自动 push 到 detail 列。自绘 `onTapGesture` 没有这个 selection 驱动;同时也没有任何地方在打开文件时把 `columnVisibility` 切到 `.detailOnly`。
- 因此 compact 下选中文件,detail 列不会被翻到前台。

### 关键事实(避免未来误判)

**state 已正确建立,仅布局未翻页。** tab 已建、`currentDocument` 已非 nil、编辑器实例已存在——文档确实已「打开」,只是 iPhone compact 布局没把 detail 列显示出来。

排查时**不要**误判为 `openFile` / `selectedFile` / 文件读取链路故障。该链路在 iPad / macOS(regular 宽度、双列同屏)上验证正常。

### 本轮处理(Phase 5A · 过渡方案 A)

Phase 5A 采用**方案 A**:compact 宽度下打开文件时把 `columnVisibility` 切到 `.detailOnly`,把 detail 列翻到前台(`Views/ContentView.swift` 的 `selectedFile` onChange)。

**这是 stage 1 的最小可用修法,不是最终形态。** 侧栏导航的正规形态(是否改用 `NavigationSplitView` 管理的 `List(selection:)`,让系统在 compact 下自动 push/pop)留待 **Phase 5 iOS 外壳设计**一并决定、届时重新评估。看到 `columnVisibility` 那段操作时,勿误判为深思熟虑的最终设计。

### 候选方案(最终形态,留 Phase 5 评估)

- **方案 A(本轮已采用,过渡)**:打开文件时 `columnVisibility = .detailOnly`。最小,但返回侧栏依赖系统/现有 toggle。
- **方案 B**:把侧栏改造成 `NavigationSplitView` 管理的 selection(`List(selection:)` 或等效),让系统在 compact 下自动 push/pop。

两方案在 regular 宽度下的行为、返回手势、以及与现有自绘选中态(左侧 accent bar,`Views/SidebarView.swift:381-387`)的兼容度各有取舍,统一到 iOS 适配阶段评估,不在此预先决定。

---

## KI-2 · iPadOS 窗口化模式下 scenePhase 不进 `.background`/`.inactive`,scenePhase flush 不触发

- **发现日期**:2026-07-26(iPad 模拟器验证 save-flush 时观察到)
- **平台**:iPadOS 26 窗口化(浮动窗口)多任务
- **状态**:已确认;是 flush 触发点的**已知覆盖缺口,不是 bug**;本轮不修
- **归属**:OS/环境行为,非 flush 逻辑缺陷

### 设计背景

save-flush 本轮实现的三个触发点(scenePhase `.background`/`.inactive`、App 退出、切 tab)构成**刻意的完备边界**——覆盖所有"内容可能长时间只在内存"的风险场景。**KI-2 是这个边界的已知例外**:在下述特定窗口化场景中,scenePhase 信号本身不产生,故该触发点不生效。

### 现象

app 以浮动窗口打开时,按 HOME 键窗口仍留在屏幕边缘,scene **不进入** `.background`/`.inactive`,因此 `InkwellApp` 的 `.onChange(of: scenePhase)`(`InkwellApp.swift`)flush 不触发,编辑内容不落盘。

### 触发条件

iPadOS 26 窗口化(浮动窗口)模式 + 按 HOME。

### 干净的后台触发(不受影响)

- **锁屏(Lock)**
- **切到另一个全屏 app**

这两种下 scene 正常进 `.background`/`.inactive`,flush 立即正确落盘(iPad 验证已证实:锁屏后 `Untitled 3.md` 由 0 字节变为完整内容)。iPhone / 真机全屏下按 HOME 也正常。

### 影响

窗口化状态下,若用户**仅按 HOME 而不锁屏、不切全屏 app**,编辑内容可能**长时间仅存于内存**;直到下一次锁屏 / 切全屏 / 切 tab / Cmd+S / 关闭 tab 才落盘。

### 关键事实(避免误判)

scenePhase flush 逻辑本身**正确**(锁屏 / 切全屏 app 场景已验证正确落盘)。这是**触发信号在特定窗口化场景下不产生**,不是 flush 未执行或写错内容。

### 候选解法(不预先选定,留「定时自动保存」议题一并设计)

- **方案 A**:补 `willResignActive`(`UIApplication` 通知)作为更早、更普适的后台信号。
- **方案 B**:定时 flush(与「定时自动保存」同源)。

两者与「定时自动保存」方案强相关,统一到该议题评估,本轮不预先决定。
