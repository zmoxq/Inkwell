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

### 本轮处理(Phase 5A · 过渡方案 A,commits `4a81637` + `7a519c8`)

Phase 5A 采用**方案 A**:compact 宽度下文件被打开/点击时,把 `NavigationSplitView` 的 **`preferredCompactColumn`** 切到 `.detail`,把编辑器列翻到前台(返回列表用系统自带返回按钮)。触发信号有二——`activeTabId` 变化(新建 / 切 tab)+ 每次行 tap 的单调 `editorRevealTick`(覆盖"返回后再点已打开的同一文件":`FileItem` 只按 url 判等,再点不改 `selectedFile`、也不改 `activeTabId`,故需独立的 per-tap 信号)。见 `Views/ContentView.swift`、`Views/SidebarView.swift`。

> 实现踩到的两个坑(详见 `PHASE_5A_IOS_ENABLEMENT.md` §四):① `columnVisibility` 只管 regular,compact 必须用 `preferredCompactColumn`;② 别依赖 url-Equatable 的 `selectedFile` 变化来驱动"点击有反应"。

**这是 stage 1 的最小可用修法,不是最终形态。** 侧栏导航的正规形态(是否改用 `NavigationSplitView` 管理的 `List(selection:)`,让系统在 compact 下自动 push/pop)留待 **Phase 5 iOS 外壳设计**一并决定、届时重新评估。看到 `preferredCompactColumn` / `editorRevealTick` 那几段时,勿误判为深思熟虑的最终设计。

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

---

## KI-3 · iPad 窗口化模式下观察到启动黑屏(未复现 / 未定性)

- **发现日期**:2026-07-28(Phase 5A step 2 的 iPad regular-width 回归检查中)
- **平台**:iPadOS 26 窗口化(浮动窗口)模式
- **状态**:**观察到,未稳定复现,未定性。留作钩子,不现在排查。**

### 现象

在 iPad Air(iPadOS 26.4)窗口化模式下启动 Inkwell,窗口出现但内容持续黑屏(此时应为纯 SwiftUI 的空状态 / 文件列表,**并非** WKWebView 区域),并伴随窗口最小化动画抽动。同一台设备上一轮(save-flush 验证)渲染正常。

### 为什么不归为「环境假象」

[[KI-2]] 已确认 iPad 窗口化模式下存在一个**真实**行为异常(scenePhase 不进 `.background`)。同一环境第二次出现异常表现,若两次都判成"环境问题"而不留痕,万一存在共同根因(窗口化生命周期 / 渲染时序)就会被永久掩盖。故留此条:第三次出现时对照本记录找共性,而不是又一次归零。

### 待办(下次复现时采集,不主动排查)

窗口尺寸与是否 compact、黑屏区域是否 WKWebView、`scenePhase` 时序、控制台 / WebContent 进程日志。

---

## KI-4 · Stock chart 时间轴日期标签在 Inkwell 内不可见

- **发现日期**:2026-05-13(PR 4' / D3 阶段)
- **平台**:Inkwell WKWebView(编辑器渲染态),对照 Safari(CDN 加载 lightweight-charts)显示正常
- **状态**:未解决,已接受为 caveat
- **归属**:WKWebView / contentEditable 渲染环境,非数据格式或 lightweight-charts 库缺陷

### 影响

`stock-chart` 块底部时间轴不显示日期文字。K 线、volume、MA、十字光标 hover 时的具体日期均正常——缺的只有 X 轴静态标签。

### 现象

同一份图表配置与数据:

- 在 Safari 中打开对照 HTML(CDN 加载 lightweight-charts)→ 日期标签正常显示
- 在 Inkwell 的 WKWebView 内 → 日期标签不可见

对照实验用三个 case(TradingView 官方配置 300px / Inkwell 配置 400px / 同配置 440px),Safari 下三个 case 全部显示日期标签。

### 已排除的可能性

| 假设 | 排除依据 |
|---|---|
| 数据格式问题(ISO 日期字符串) | Safari 对照实验中同数据正常显示 |
| lightweight-charts 库本身缺陷 | 官方默认配置在 Safari 下正常 |
| 容器高度不足 | 试过 +30 / +35 / +40 / +60 offset,均无效 |
| autoSize 与显式 width/height 冲突 | 移除冲突项后仍不显示 |
| volume series 的 priceScaleId 配置 | 改为独立 pane / overlay 均无变化 |

### 已知诊断证据

Canvas 位置诊断显示:**time-scale 的 canvas 渲染在宿主容器边界下方约 19px 处**,被 `stock-chart-note` 元素覆盖。所有 console 指标(canvas 尺寸、timeScale visible 状态、textColor)都显示"应该能显示",但视觉上不可见。

### 未尝试的五个方向

1. **iframe 隔离** — 把 chart 放进 iframe,脱离 contentEditable 宿主的 CSS 与布局上下文
2. **contentEditable 宿主环境 quirks** — 排查 contenteditable 容器对内部 canvas 定位/裁剪的影响(注:Inkwell 无第三方编辑器框架,是自写实现)
3. **WKWebView 与 Safari 的渲染差异** — 定位两者在 canvas 合成层上的具体分歧
4. **inspect lightweight-charts 源码** — 找 time scale canvas 的定位计算逻辑
5. **手动绘制时间轴** — 放弃库的 time scale,自绘 X 轴标签

### 当前处理方式

接受为已知 caveat。图表仍传达约 90% 的复盘价值——价格形态、成交量、均线均可读,hover 十字光标可读出精确日期。X 轴静态标签属 nice-to-have。

### 已确认的反模式

**不要再用 `config.height + N` 的 fudge factor 修这个问题。** 该做法在不同 DPR、字体设置、iOS/macOS 之间不稳定,是架构层面不成立的解法。
