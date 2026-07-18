# 交互编辑路径自动化 — 设计方案

> 状态:设计定稿(2026-07-17)。实现留待后续,按一步一 commit / 每场景先红后绿推进。
> 承载:方案 A(execCommand + 定向 keydown),经离屏 WKWebView 可行性验证。

## 1. 动机

现有 `RoundTripTests` 覆盖**纯 parse → decorate → serialize** 路径。但磁盘上最恶性的
损坏(标题吞并相邻块内容、`<span style>` 泄漏)在纯路径**不复现**——它们住在
**交互编辑路径**:EditMode 进出、键入、删除触发的 contentEditable 原生编辑 + LiveConverter。
本方案把测试网扩展到这片黑暗。

## 2. 可行性(2026-07-17 验证)

离屏 WKWebView(复用 `RoundTripHarness` 的 bundle + scheme handler)中:

- `document.execCommand('insertText' | 'delete' | 'forwardDelete' | 'insertParagraph')`
  驱动**真实** contentEditable 管线:触发 input → `LiveConverter.onInput`,执行原生块合并/拆分。
  实测 `execCommand('delete')` 在标题首返回 true 并真实改动 DOM。
- 合成 `KeyboardEvent('keydown')` 到达编辑器按键处理器(`LiveConverter.onEnter`、
  `<pre>` 的 Enter/Backspace 拦截、EditMode 方向键/Backspace 入编辑)。
- `EditMode.requestEnterEdit / requestLeaveEdit` 可直接调用;Selection/Range 定位光标;
  `getMarkdown()` + DOM 内省可用。

**局限(已接受)**:离屏 WKWebView 无法从 JS 合成硬件级原生按键。execCommand + 定向
keydown 覆盖「键入/删除/Enter/进出编辑」到达的**同一段 JS 代码路径**,但非逐比特等同
真实敲键。若某 bug 只在真实按键下复现,再引 XCUITest 兜底(方案 B,当前不做)。

## 3. Harness 扩展

在 `RoundTripHarness`(或子类 `InteractiveHarness`)上加交互原语,均经 `evaluateJavaScript`:

| 原语 | 实现 |
|---|---|
| `placeCaret(selector, offset)` | Range.setStart + collapse |
| `selectRange(sel1, off1, sel2, off2)` | 跨节点 Range(跨块选区删除用) |
| `typeText(s)` | `execCommand('insertText', false, s)` |
| `backspace()` | `execCommand('delete')` |
| `forwardDelete()` | `execCommand('forwardDelete')` |
| `pressEnter()` | dispatch keydown Enter(经 LiveConverter/fence 拦截) |
| `enterEdit(selector)` | `EditMode.requestEnterEdit(el, {via})` |
| `leaveEdit()` | `EditMode.requestLeaveEdit(fence)` |
| `readDom()` / `serialize()` | innerHTML 快照 / getMarkdown |

每个原语后有一个 settle(复用稳定性轮询)。

## 4. 断言:每场景双重

**(a) round-trip 完整性**:操作序列后 `getMarkdown()` 干净(或对金标 .md,当序列有意变换内容)。

**(b) DOM 完整性不变量**(损坏探测器,任何一条违反即失败):

1. **标题不含块级 HTML**:`h1..h6` 内只允许 inline / 文本 / 已知 UI 装饰
   (`.inkwell-fold-toggle` / `.inkwell-drag-handle`)。出现 `<pre>` / `<div>` / `<span style>` = 吞并。
2. **hljs 颜色 span 不越界**:`<span style="color:rgb(...)">` 不得出现在 `<pre>`/code 上下文之外。
3. **renderer 内容不并入他块**:带 `data-source-b64` 的节点只作为独立块存在,内容不渗入相邻块。
4. **无残留编辑态**:序列结束(且已 leave)后 `EditMode._editingFence === null`。

不变量集中在一个 JS 帮助函数里,harness 暴露 `checkInvariants()` 返回违反项列表。

## 5. 场景清单(Swift 测试方法,每方法一操作序列)

操作序列不是 .md 能表达的,故写成 Swift 测试方法调 harness API;少数有意变换内容的用金标 .md。

1. **进出编辑各 renderer 块**:$$ math / mermaid / code 各一次 enterEdit → leaveEdit → round-trip 干净 + 不变量。
2. **标题吞并疑区(重点)**:代码/mermaid/math 块**后接标题**,光标置标题首,`backspace()`。
   变体:标题空 vs 非空、前块渲染态 vs 编辑态、单次 vs 连续 backspace。
3. **块尾 forwardDelete**:段落/标题尾 `forwardDelete()`,前接列表/代码/标题。
4. **现场转换后离开**:`typeText('$$')` + `pressEnter()`、`# ` + 文本、```` ``` ```` + lang + Enter → leaveEdit → round-trip。
5. **快速进出压测**:同一块 enterEdit/leaveEdit 连续 N 次,末态 round-trip + 不变量。
6. **跨块选区删除**:`selectRange` 从段落跨入标题,`backspace()`。

场景 2 与 6 是标题吞并最可能的复现路径,优先。

## 实施记录(2026-07-17)

**已落地**:`RoundTripHarness` 交互原语 + `window.__IE` 注入(caret / pressKey / editCycle / invariants / selectFromEndIntoCode)+ `InteractiveEditTests`。

**关键方法论修正**:实测 `execCommand('forwardDelete')` **既不触发 keydown 也不触发 `beforeinput`**(`beforeinputFired: []`),直接走原生编辑——它触发损坏但**绕过一切守卫**,故不能用来验证守卫修复。删除类守卫一律经**合成 keydown 检查 `defaultPrevented`**:真实按键走同一 keydown 路径,`preventDefault` 正是阻止 WebKit 原生合并的机制。这是 Approach A 在删除场景下的落地形态。合成 keydown 无法触发原生合并(untrusted),故断言的是「守卫是否 preventDefault」,不是「合并是否发生」——对真实用户等价。

**已修的标题吞并(两条)**:
- 场景 2 边界 forward-delete:标题/段落尾 Delete、下一块受保护 → 加 keydown Delete 守卫(镜像现有 Backspace 守卫)。`testDelete{Heading,Paragraph}EndBeforeCode` 红→绿。
- 场景 6 跨块选区部分切入:非塌陷选区端点严格落在受保护块内部且有残余 → preventDefault(方案 A);完整包含则放行。`testCrossBlockDeletePartialCut` 红→绿,`…FullBlockIsAllowed` 绿。

**已验证干净(绿基线)**:场景 1 进出编辑 math/mermaid round-trip + DOM 不变量;现有 Backspace@code-start 守卫。

**留待后续**:场景 3(块尾 forwardDelete 其他组合)、4(现场转换后离开)、5(快速进出压测)可增量补入。#7 段落模型 + Enter/Shift+Enter 交互场景作为独立 PR。

### 补充实施(2026-07-17)

**#7 Enter/Shift+Enter**:已进网(`testShiftEnterInsertsHardBreak`、`testShiftEnterGuardedDuringComposition`)。

**beforeinput 纵深守卫**:验证结论——菜单/听写/系统替换类删除按 Input Events 规范 fire `beforeinput`(deleteContentForward/Backward)但**不 fire keydown**,是 keydown 守卫盲区;`execCommand` 两者都不 fire,属程序化非用户路径不计。已加 beforeinput 兜底(镜像边界/跨块逻辑),经合成 `beforeinput`(可 dispatch 且可取消,与 execCommand 不同)验证:4 个测试覆盖受保护边界拦截 + mid-content/完整选区放行。

**undo 五序列**:D1 裁决——enter/leave-edit 走 `replaceChild`,不进浏览器 undo 栈;`execCommand('undo')` 跨转换为**无操作**,且**不损坏**(实测:块结构稳定、无 HTML 泄漏、md 幂等)。四序列已自动化进网:
- 序列 1 打字离开渲染 → undo(`testUndoAfterTypeLeaveRender`)
- 序列 2 空块退化 → undo(`testUndoAfterEmptyBlockDegrade`)
- 序列 3 enter-edit 立即 undo(`testUndoImmediatelyAfterEnterEdit`,undo 后仍在编辑态=D1 正确)
- 序列 5 多块编辑多级 undo(`testUndoMultiBlockMultiLevel`)

**序列 4(abort-to-edit 中断)未自动化,留人工**:该序列需在异步渲染**在飞**时插入 enter-edit 以触发 abort;实测 mermaid 加载 25ms 后 block 已渲染完、abort controller 已不存在,abort 窗口 <25ms,harness 的 evaluateJavaScript 往返 + loadMarkdown/render 无法在该窗口内可靠插入 enter-edit(多次尝试导致 harness 卡死)。人工验收:加载一个较重的 mermaid 图,在其渲染动画未完成时点击进入编辑,再 Cmd+Z,确认不残留半渲染 DOM、不崩、源码完整。

## 6. 文件落点

- Harness 扩展:`InkwellTests/RoundTripHarness.swift`(加原语)或新 `InteractiveHarness.swift`。
- 场景:`InkwellTests/InteractiveEditTests.swift`(新)。
- 金标(如需):`tests/roundtrip/fixtures/*.expected.md`,复用 §NORMALIZATION 的金标机制。

## 7. 实施顺序(后续程)

一步一 commit,每场景先红后绿:先落 harness 原语 + 不变量检查(自身用一个已知干净序列验证为绿),
再逐场景加。若某场景**复现**了标题吞并 → 该场景即为红,定位 contentEditable 合并根因后修,转绿。
若系统扫完仍无复现 → 如实报告,判定磁盘损坏属历史/已消解(与 Step 3 的纯路径结论一致)。
