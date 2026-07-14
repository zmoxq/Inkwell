# Inkwell Phase 3.5 — LiveConverter × Edit-Mode 状态机设计

> **Status**: 已完成(全量回归通过)
> **Document Version**: 1.5
> **Last Updated**: 2026-07-14
> **前置文档**: `INKWELL_ROADMAP.md`(Phase 3.5-A)、`PHASE_3_ARCHITECTURE.md` v2.0(附录 C.3 遗留 TODO)
> **适用范围**: editor.html 内 BlockRenderer 的现场输入接入与 typora-style 编辑态

---

## 一、问题定义

Phase 3 只打通了 **parser 路径**(loadMarkdown 冷加载):占位符 → `_resolvePendingRenderers()`。**LiveConverter 路径**(用户现场输入)仍然只生成 `<pre><code>`,已注册的 renderer(mermaid / math / stockchart)必须重载文件才可见。

本 Phase 补上第二条路径,并顺带兑现 DOM Contract 中早已预留但从未实现的 `editStyle: "typora"` 行为——两者本质是**同一个状态机的两个转换方向**。

---

## 二、决策记录

| # | 决策 | 选择 | 拒绝的方案 | 原因 |
|---|------|------|-----------|------|
| 1 | 现场输入的渲染触发时机 | **光标离开块时** | 闭合围栏输入完成即渲染 | 与 Typora 心智模型一致;避免"改一个字符就弹跳"的往复;与"进入渲染块切回源码"构成对称的状态机 |
| 2 | typora 编辑态呈现 | **就地替换为源码块** | 渲染物保留 + 下方展开编辑区 | DOM 简单;selection 管理成本低;用户预期已被 Typora 教育;方案 B 属过度设计 |
| 3 | loading 中用户点回块内 | **abort 渲染,立即回编辑态** | 等渲染完成再允许进入 | AbortSignal 机制为此而生;"点了就能编辑"优先于"看完渲染结果" |

---

## 三、状态机

每个受管块(源码可被注册 renderer 匹配的 fenced block)在以下四态之间转换:

```
                  enter-edit intent
   ┌────────────────────────────────────────┐
   │                                        │
   ▼                                        │
[editing] ──leave-edit intent──▶ [rendering] ──render 完成──▶ [rendered]
   ▲                                │                            │
   │      enter-edit intent         │                            │
   └────────────────────────────────┘                            │
          (abort in-flight, 决策3)                                │
   ▲                                                             │
   └──────────────────── enter-edit intent ──────────────────────┘

[plain] = 源码不匹配任何注册 renderer 的普通 fenced block,
          走既有 hljs 装饰路径,不进入本状态机。
          editing → leave 时若语言已被用户改为未注册语言,退化为 plain。
```

### 状态定义

| 状态 | DOM 形态 | 说明 |
|------|---------|------|
| `editing` | `<pre><code>` + 标记 class `inkwell-live-fence` + `data-fence-language` | 正常 contentEditable 源码,LiveConverter 现有产物加标记 |
| `rendering` | renderer root(`.inkwell-block-renderer`),`.renderer-output` 为 loading 占位 | `render()` 已同步返回 root,runAsync in-flight |
| `rendered` | renderer root,输出就绪 | 与 parser 路径产物完全同构 |
| `plain` | 普通 `<pre><code>` | 不受管,hljs 装饰 |

**关键约束**:`rendering`/`rendered` 的 DOM 与 parser 路径产物**逐属性一致**(同一个 `createBlockRoot`),serializer 无需感知块的出生路径。

---

## 四、Intent 抽象(为 Phase 5 预留)

状态转换的触发一律收敛为两个语义意图,输入设备事件只负责翻译成意图:

```javascript
EditMode.requestEnterEdit(blockRoot, hint)
// hint: { via: "click" | "arrow-down" | "arrow-up" | "backspace" | "edit-button",
//         point?: {x, y} }   // click 时的坐标,用于光标定位

EditMode.requestLeaveEdit(fenceEl)
// 由 selection 离开检测统一发出
```

Phase 5 触控适配时,tap/长按翻译为同一组 intent,状态机零改动。

### 桌面端事件 → intent 翻译表

| 事件 | 条件 | intent |
|------|------|--------|
| `mousedown` 落在 `.inkwell-block-renderer` 且 `editStyle="typora"` | — | enterEdit(via: click, point) |
| `keydown` ↓/→ | 光标位于块前一个可编辑位置的末尾 | enterEdit(via: arrow-down) |
| `keydown` ↑/← | 光标位于块后一个可编辑位置的开头 | enterEdit(via: arrow-up) |
| `keydown` Backspace | 光标紧邻块之后的开头 | enterEdit(via: backspace)(**不删除块**,进入编辑态,光标置末尾) |
| click `.renderer-edit-action` | `editStyle="edit-button"` | enterEdit(via: edit-button) |
| `selectionchange` | 光标不再位于某 `inkwell-live-fence` 内 | leaveEdit |
| 编辑器 blur / 保存触发 | 存在 editing 态块 | leaveEdit(全部) |

`contenteditable="false"` 保证点击渲染块不会天然产生 caret,mousedown 拦截是唯一入口,无竞争路径。

---

## 五、转换细节

### 5.1 rendered → editing(enter-edit)

```
1. IME 检查:若全局 composition 进行中 → 排队到 compositionend(复用既有保护)
2. 读 data-source-b64 → 解码得到含围栏的源码文本
3. 构造 <pre><code class="inkwell-live-fence" data-fence-language="...">源码</code></pre>
4. 整体替换 renderer root(若该 root 有 in-flight runAsync → abort,决策 3)
5. 光标定位:
   - via: click       → 替换后用 caretRangeFromPoint(point) 尽力定位;失败则内容首
   - via: arrow-down  → 源码第一行行首
   - via: arrow-up 或 backspace → 源码最后一行行尾
   - via: edit-button → 内容首
```

### 5.2 editing → rendering → rendered(leave-edit)

```
1. IME 检查:composition 中 → 延迟到 compositionend
2. 读取源码文本,解析围栏头,询问 ExtensionRegistry.findBlockRenderer
   ├─ 无匹配 → 退化 plain:摘除 inkwell-live-fence 标记,交 hljs 装饰,结束
   └─ 有匹配 ↓
3. 直接调 renderer.render()(safeCall 包裹)——注意:此路径在 JS 运行时内,
   **不需要占位符**;占位符只为 parser 的字符串路径而生(C.2)
4. render 同步返回 root(内含 data-source-b64)→ 整体替换 <pre>
5. runAsync 照常工作(loading → 输出 / onError)
6. render 同步抛错 → 既有故障行为表:error fallback block,源码不丢
```

### 5.3 rendering 中 enter-edit(决策 3)

runAsync 的"同 root 单任务 + 新任务 abort 旧任务"保证已覆盖大半;唯一新增:enter-edit 显式 abort 后**不等待**任务收尾,立即执行 5.1 的替换。renderer 的 task 内已有 `if (signal.aborted) return` 纪律,不会写回已脱离文档的 DOM。

### 5.4 LiveConverter 侧改动

现有行为(闭合围栏 → 生成 `<pre><code>`)**保持不变**——这正是 editing 态。唯一改动:生成时附加 `inkwell-live-fence` 标记与 `data-fence-language`,使其进入状态机管辖。渲染由后续的 leave-edit 统一触发,LiveConverter 不直接调 renderer。

---

## 六、Serializer 影响

两态各自的序列化路径均已存在,无新逻辑:

| 状态 | 序列化来源 |
|------|-----------|
| rendered / rendering | `data-source-b64`(既有优先级第 1 条) |
| editing / plain | `<pre><code>` 文本本身(既有 fenced block 路径) |

**验收含义**:保存动作发生在任意状态下,磁盘产物一致。保存前对 editing 态块不强制转出——源码本来就是权威。

---

## 七、明确不做(本 Phase 边界)

- ❌ 编辑态语法高亮(编辑中的 mermaid 源码不做着色;Typora 同样不做)
- ❌ 双栏/预览式编辑
- ❌ 点击坐标到源码字符的精确映射(caretRangeFromPoint 尽力而为即可)
- ❌ InlineRenderer 的编辑态(`==highlight==` 维持现状,属 InlineRegistry v2 议题)

---

## 八、实施顺序

```
1. EditMode 骨架:intent 入口 + 状态标记 + IME 排队(不接 UI 事件)
2. 5.2 leave-edit 路径:fence → renderer 直调转换(先用手动调用验证)
3. LiveConverter 打标记;selectionchange 离开检测接入 → 现场输入端到端跑通
4. 5.1 enter-edit 路径:mousedown 拦截 + 光标定位
5. 方向键 / backspace 进入;edit-button 契约兑现
6. 决策 3 的 abort 分支;快速进出连打压力测试
7. 回归:parser 路径、主题切换重渲染、carousel、find/replace 全量过一遍
```

## 九、验收标准

- 现场输入 mermaid / math / stockchart 围栏,光标离开即渲染,不重载文件
- 点击渲染块 → 源码就地出现,光标落点合理;编辑后离开 → 重渲染
- 方向键上/下穿越渲染块可进入编辑;Backspace 紧邻块后不误删块
- loading 中点回 → 立即可编辑,无竞态残影(连续快速进出 20 次无异常)
- 中文 IME 组合输入横跨任何转换时机,composition 不撕裂
- 语言改为未注册值(如 mermaid→js)→ 正确退化为 hljs 普通代码块
- 任意状态下保存,磁盘 .md 与编辑语义一致,round-trip 无损
- render 同步抛错 / runAsync 抛错 → 既有 error fallback,源码可再次进入编辑
- 保护性空段落(文档首/尾)不得在序列化产物中产生多余空行,round-trip 前后逐字节一致

## 十、Open Questions(实施时需对照现有代码确认)

1. **Undo/redo**:整块 DOM 替换与 contentEditable 原生撤销栈的关系——需确认 editor.html 当前的 undo 机制(原生 or 自管),决定转换是否要作为不可撤销边界或自定义 undo 单元。
2. **selectionchange 频率**:离开检测是否需要 debounce,取决于现有 selection 管理代码的形态。
3. **块前后无可编辑位置**(文档首/尾紧邻渲染块)的方向键进入路径,需确认现有空段落策略。

---

## 附录:Open Questions 裁决记录

> 实施前对照 `Resources/editor.html` 现有代码确认,2026-07-08 裁决。

### OQ1: Undo/redo — 不可撤销边界

**结论**:enter-edit 和 leave-edit 是**不可撤销边界**,不引入自管 undo 系统。

**代码依据**:

- editor.html 全文无 `undo`/`redo`/`UndoManager`/`MutationObserver` 任何痕迹,undo/redo 完全依赖浏览器原生 contentEditable 撤销栈。
- `setupKeyboardShortcuts()` (L5168) 不拦截 Cmd+Z / Cmd+Shift+Z,由浏览器原生处理。
- 格式命令走 `document.execCommand()` (L5208),天然进入浏览器 undo 栈。

**行为**:

- 整块 DOM 替换(`replaceChild`)不是 `execCommand`,浏览器不为其建立 undo 记录。
- 进入编辑态后,编辑态内部的输入修改 undo 正常工作(普通 contentEditable 输入)。
- 离开编辑态→渲染后,之前的编辑 undo 信息丢失。

**实现方式**:不需要额外代码。`replaceChild` 本身即构成不可撤销边界——浏览器原生行为自动满足。

**⚠️ 设计债**:UX 代价——用户的 Cmd+Z 撤销不跨越编辑态转换。Typora 行为一致,短期可接受。若未来用户反馈强烈,需引入自管 undo 系统(工程量大),届时另立设计文档。

### OQ2: selectionchange 频率 — 不需要 debounce

**结论**:leave-edit 检测直接在 selectionchange handler 里同步判断,不加 debounce。

**代码依据**:

- 现有两处 selectionchange 监听(FocusMode L4402、Editor L4908)均为直接调用、无 debounce。
- `updateSelectionState()` (L5432) 是同步轻量级 DOM 祖先遍历,已验证无性能问题。
- 现有"光标离开 code block → `rehighlightAll()`"模式 (L5447) 与 leave-edit 检测是同类操作,可并列。
- IME 保护不靠 debounce,靠 composition 状态检查(LiveConverter L2881 的 `e.isComposing` 模式)。

**实现方式**:在现有 selectionchange handler 内增加 `closest('.inkwell-live-fence')` 判断,与 `_wasInCodeBlock` 模式并列。

### OQ3: 文档首尾空段落策略 — 按需插入保护性空段落

**结论**:在 renderer 产物就位后检查文档首尾,按需插入 `<p><br></p>`。

**代码依据**:

- MarkdownParser.parse() (L2425) 不在首尾追加保护性段落,`return html` (L2674) 无后处理。
- loadMarkdown() (L4935) 直接 `innerHTML = ...`,不追加保护元素。
- LiveConverter.onEnter() 在 heading/hr/blockquote 后追加 `<p><br></p>` (L2924, L2938, L2982),但 fenced code block 不追加 (L2954)。
- 无全局性"确保文档首尾有空段落"机制。

**影响**:文档以 fenced block 开头/结尾时,渲染后首/尾元素为 `.inkwell-block-renderer`,前/后无可编辑落点;方向键 enter-edit 路径不可达。

**实现方式**:

1. `_resolvePendingRenderers()` 完成后,检查 `#editor.firstElementChild` / `lastElementChild` 是否为 `.inkwell-block-renderer`,是则插入 `<p><br></p>`。
2. leave-edit 产出 renderer root 后,同样检查。
3. Serializer 现有逻辑已正确处理空 `<p><br></p>`(输出空行),round-trip 无影响——但需验收确认不产生多余空行(已补入第九节验收标准)。

### 设计债:UI 装饰物与内容共存于 contentEditable DOM

**现状**:DragSort 在每个块元素内注入 `<span class="inkwell-drag-handle">⠿</span>`,其 `textContent` 被 `block.textContent` 包含,破坏所有 `^` 锚定的 LiveConverter 正则匹配(heading / hr / fence / quote / list)。

**当前处理**:`LiveConverter.getBlockSourceText(el)` 遍历 `childNodes` 时显式跳过 `.inkwell-drag-handle`。仅此一种装饰物,硬编码可控。

**升级时机**:若出现第二种注入 contentEditable DOM 的 UI 装饰物,应升级为统一标记属性(如 `data-inkwell-ui`)过滤,而非逐一枚举 class name。

### 实施记录:§5.2 leave-edit 块类型派发扩展

**设计文档盲区**:§5.2 的 leave-edit 路径和 §5.1 的 enter-edit 路径均以围栏代码块(` ``` `)为中心描述,未明确涵盖 `display-math`(`$$...$$`)块类型。实施时 `_doEnterEdit` / `_doLeaveEdit` 最初仅处理围栏格式,导致 KaTeX 公式块点击进入编辑后离开时无法重渲染。

**实施扩展**:Step 4 实现时按块类型派发,同时覆盖两种定界符格式:

- `_doEnterEdit`:先尝试 `$$` 匹配(`/^\$\$\s*\n?([\s\S]*?)\n?\$\$\s*$/`),再尝试 ` ``` ` 匹配。检测结果存入 `<pre data-block-type="display-math|fenced-code">`。
- `_doLeaveEdit`:读取 `data-block-type`,按类型构造不同的 block descriptor——`display-math` 提供 `{ type, content, raw }`,`fenced-code` 提供 `{ type, language, content }`。

**未来新增块类型的必经改动点**:若引入第三种非围栏块类型(如 `:::` 容器指令),`_doEnterEdit` 的定界符检测和 `_doLeaveEdit` 的 block descriptor 构造是必须扩展的两个位置。

### 实施记录:§8 七步实施 Commit 对照

| 步骤 | Commit | 说明 |
|------|--------|------|
| Steps 1–3 | `c5e55fa` | EditMode 骨架 + mousedown 拦截 + selectionchange leave-edit 检测 + hljs guard + getBlockSourceText fix。因未及时逐步提交,squashed 为一个 commit。 |
| Step 4 | `a1c9858` | `_doEnterEdit` / `_doLeaveEdit` 完整实现,含 fenced-code 和 display-math 块类型派发。 |
| Step 5 | `6b44551` | 方向键 ↑↓←→ / Backspace 进入编辑态 + edit-button 契约。因与 Enter fix 同批提交被包含在该 commit 中。 |
| Step 6 | `83fea03` + `52c0300` | leave-before-enter guard(点击新块时先离开旧块)+ 空文档 init 路径 ensureEdgeGaps。Abort 分支由 Step 4 已覆盖(无需新增代码)。 |
| Step 7 | `9f90529` + `f74037b` | blur 语义收窄(document.hasFocus guard)+ serializer live-fence 派发 + carousel ensureEdgeGaps 覆盖 + 全量回归通过 |

### 实施记录:实施中发现并修复的 Pre-existing Bug

| Bug | Commit | 说明 |
|-----|--------|------|
| DragSort handle 污染 textContent | `c5e55fa` | `<span class="inkwell-drag-handle">⠿</span>` 被 `block.textContent` 包含,破坏 LiveConverter 所有 `^` 锚定正则。修复:`getBlockSourceText(el)` 排除 `.inkwell-drag-handle`。 |
| Enter 在 `<pre>` 末尾复制整块 | `6b44551` | WebKit contentEditable 默认行为在 `<pre>` 末尾按 Enter 时复制整个元素。修复:拦截 Enter,直接 DOM 插入 `\n`。 |
| Backspace 在 `<pre>` 首行合并/删除 | `4f5e957` | WebKit 默认 Backspace 在块首合并相邻块,破坏代码块第一行。修复:首行 preventDefault + 空块退化为 `<p>`。 |
| 守护段落缺失(OQ3 覆盖缺口) | `a635c79` | 文档首/尾为 `<pre>` 或 `.inkwell-block-renderer` 时无可编辑落点。修复:`ensureEdgeGaps()` 在冷加载、LiveConverter、leave-edit 三路径统一检查。 |
| 空文档无 DragSort / ensureEdgeGaps 初始化 | `52c0300` | 新建文档(空内容)不走 `loadMarkdown`,跳过初始化。修复:Editor.init() 中 postMessage 前调用。 |

### 设计债汇总

| 编号 | 债务 | 来源 | 升级条件 |
|------|------|------|----------|
| D1 | Undo 不可撤销边界 | OQ1 裁决 | enter/leave-edit 的 `replaceChild` 不进浏览器 undo 栈。`<pre>` 内 Enter 直接 DOM 插入的换行也不进撤销栈。若用户反馈强烈,需引入自管 undo 系统。 |
| D2 | UI 装饰物排除硬编码 | getBlockSourceText | 仅排除 `.inkwell-drag-handle`。第二种 UI 装饰物出现时需升级为统一 `data-inkwell-ui` 属性过滤。 |
| D3 | §5.2 块类型派发 | Step 4 实施 | enter/leave-edit 按定界符格式派发(`` ``` `` 和 `$$`)。新增非围栏块类型时,`_doEnterEdit` 定界符检测和 `_doLeaveEdit` block descriptor 构造是必经改动点。 |

### 契约变更:§4 blur 语义收窄

**Commit**: `9f90529`

**原设计**(§4 事件表第 6 行):

> | 编辑器 blur / 保存触发 | 存在 editing 态块 | leaveEdit(全部) |

**实施偏离**:窗口失活(用户切换到其他应用)不再触发 `leaveEdit`。`selectionchange` handler 增加 `document.hasFocus()` 守卫,仅在编辑器持有焦点时检测光标离开 fence。

**根因**:WebKit 中窗口失焦时 `selectionchange` 事件仍然触发,且选区可能被移出 live fence 范围。对于刚创建的空 fence(用户尚未输入内容即切换窗口去复制代码),`_doLeaveEdit` 会将空内容交给 renderer 渲染,产生不可编辑的空渲染块,且 `ensureEdgeGaps` 可能清理相邻空段落,导致编辑上下文丢失。

**安全性依据**:编辑态 fence 序列化无损——`getMarkdown()` → serializer 路径已正确处理 `<pre data-block-type>` 内容,即使保存动作发生在编辑态,磁盘产物仍为合法 Markdown。因此窗口失活时无需强制 leave-edit 来保护数据完整性。

**收窄后的 blur 语义**:

| 场景 | 行为 |
|------|------|
| 编辑器内部点击其他位置 | `selectionchange` 检测光标离开 fence → `leaveEdit` ✓ |
| 窗口失活(切换应用) | `document.hasFocus()` 为 false → 不触发 `leaveEdit` |
| 保存触发(`getMarkdown`) | serializer 直接序列化 fence 内容 → 无需 leave-edit |

---

*Document version: 1.5 — blur 语义收窄契约变更、Step 7 回归完成、serializer live-fence 修复、carousel ensureEdgeGaps 覆盖*
