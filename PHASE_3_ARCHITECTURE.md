# Inkwell Phase 3 — 扩展架构

> **Status**: PR 1、PR 2 已完成。当前活跃扩展：`highlight-code`、`highlight-mark`、`mermaid`。
> **Document Version**: 2.1 — 增补 §3.4 UI 装饰排除契约(`data-inkwell-ui`)
> **Last Updated**: 2026-07-20
> **适用范围**: Inkwell macOS/iOS WYSIWYG Markdown 编辑器,editor.html 内的扩展机制

---

## 一、设计哲学

### 目标

为 Inkwell 提供一个稳定的扩展接入点,让所有非核心渲染逻辑(代码高亮、Mermaid、KaTeX、timeline 等)通过统一契约接入,**不耦合到编辑器核心**。

### 不是

- ❌ 第三方插件平台
- ❌ 动态加载系统
- ❌ 沙箱化运行时
- ❌ 用户级插件生态

### 核心约束

1. **单文件运行时**:editor.html 内置一切,符合零依赖哲学
2. **Markdown 源码绝不丢失**:任何扩展故障都不能破坏 round-trip
3. **编辑器核心稳定性优先于扩展灵活性**
4. **接口为未来拆分留位置,但不为未来的拆分做工程**

---

## 二、架构总览

```
editor.html
├── Core
│   ├── Markdown Parser (输出占位符)
│   ├── Serializer (优先读 base64 源码)
│   ├── Editor State / Selection / IME 管理
│   ├── _resolvePendingRenderers() (占位符 → 真 DOM)
│   ├── _notifyRerender(trigger)    (主题切换等触发)
│   └── Swift ↔ JS Bridge
│
├── ExtensionRegistry
│   ├── BlockRenderer    注册与分发  (接管块渲染)
│   ├── BlockDecorator   注册与分发  (装饰已渲染 DOM)
│   ├── InlineRenderer   注册与分发  (受限版,行内文本替换)
│   ├── runAsync 任务管理 (含 AbortSignal)
│   ├── 重渲染调度 (selection/IME/scroll 保护)
│   └── 错误隔离 + reportToSwift
│
├── Built-in Extensions
│   ├── highlight-code  (BlockDecorator)
│   ├── highlight-mark  (InlineRenderer)
│   └── mermaid         (BlockRenderer + rerenderOn:["theme-change"])
│
└── WebAssets 资产层
    └── inkwell-asset:// scheme → Bundle 内 WebAssets/ 目录
        (供大型 JS 库如 mermaid.min.js 引用,不污染用户文档目录)
```

**关键决策**:所有扩展物理上仍在 editor.html 内,通过清晰的区段注释组织。**不引入 build step,不拆分文件**。等 editor.html 真的影响开发效率(8000+ 行)再讨论拆分,届时 Registry 接口已为拆分做好准备。

---

## 三、三类扩展接口

实施过程中确认扩展有三种本质不同的形态,每种对应一类接口。区分依据是**对 DOM 所有权的归属**。

| 类型 | DOM 所有权 | 是否产出 `data-source-b64` 包裹 | 当前实例 |
|------|------|------|------|
| **BlockRenderer** | 接管整个块的渲染 | ✅ | `mermaid` |
| **BlockDecorator** | 装饰 core 已渲染的 DOM | ❌ | `highlight-code` |
| **InlineRenderer** | 行内文本片段替换 | n/a | `highlight-mark` |

> **为什么三类而不是两类**:highlight.js 不接管 fenced code 渲染——core 已经产出了 `<pre><code>`,它只是在上面着色。强行套 BlockRenderer 会让那个接口同时承担"接管"和"装饰"两套语义。KaTeX inline 未来很可能也是 Decorator 性质(在已渲染文本里找 `$...$` 替换),所以这个分类有前瞻意义。

### 3.1 BlockRenderer

接管 fenced code block 的整个渲染,产出带 `data-source-b64` 包裹的自治 DOM。

```javascript
ExtensionRegistry.registerBlock({
  name: "mermaid",                    // 必填,全局唯一
  type: "fenced-code",                // 必填,第一版仅支持此类型
  priority: 0,                        // 可选,匹配优先级

  match(block, context): boolean,     // 必填
  render(block, context): HTMLElement,// 必填,必须同步返回 root
  serialize(root, context): string,   // 可选,默认走 context.getSourceMarkdown

  editStyle: "typora",                // "typora" | "edit-button"
  capabilities: {
    rerenderOn: []                    // 例: ["theme-change"]
  }
})
```

**DOM Contract**:

```html
<div class="inkwell-block-renderer"
     data-renderer="mermaid"
     data-language="mermaid"
     data-edit-style="typora"
     data-source-b64="YGBgbWVybWFpZAouLi4="
     contenteditable="false">
  <div class="renderer-output">
    <!-- 实际渲染内容 -->
  </div>
  <!-- edit-style="edit-button" 时额外添加 -->
  <button class="renderer-edit-action" type="button">Edit Source</button>
</div>
```

| 属性 | 必填 | 用途 |
|------|------|------|
| `contenteditable="false"` | ✅ | 防止 DOM 编辑污染源码 |
| `data-source-b64` | ✅ | base64 编码的原始 Markdown(含围栏),无转义问题 |
| `data-renderer` | ✅ | serialize 时派发到正确的 renderer |
| `data-language` | 可选 | 便于 CSS 选择和调试 |
| `data-edit-style` | ✅ | 决定光标进入此 block 的行为(typora 切源码 / edit-button 弹按钮) |

### 3.2 BlockDecorator

装饰 core 已渲染好的 DOM,**不接管所有权,不产生 b64 包裹**。

```javascript
ExtensionRegistry.registerBlockDecorator({
  name: "highlight-code",
  selector: "pre > code",             // 匹配的 CSS 选择器
  decorate(el, context): void,        // 在 el 上原地修改
  capabilities: {
    rerenderOn: ["theme-change"]      // 例如 dark/light hljs 主题切换
  }
})
```

Decorator **不需要 serialize**:源码本来就在 core 渲染的 `<pre><code>` 文本里,装饰不改变结构,序列化由 core 默认逻辑处理。

### 3.3 InlineRenderer (受限版 v1)

```javascript
ExtensionRegistry.registerInline({
  name: "highlight-mark",
  pattern: /==([^=\n]+)==/g,          // 简单字符串替换
  render(captures, context): HTMLElement
  // 故意不提供 serialize:core 通过 data-source-b64 / 节点反序列化统一处理
})
```

**v1 明确限制**:

- 仅支持简单文本替换,不嵌套
- 不跨行
- 不感知 code span / escape / emphasis 上下文
- KaTeX inline、复杂 mention 等需要 parser-aware 扩展点,**留待 InlineRegistry v2**(见路线图 PR 5)

### 3.4 UI 装饰排除契约(`data-inkwell-ui`)

DOM 中存在**非内容**元素:`renderer-edit-action` 按钮、loading 占位、错误 UI、DragSort 拖拽柄、标题折叠钮、carousel 导航控件等。它们必须活在 live DOM 里(供交互),但绝不能进入任何"内容出口"。此前它们不落盘靠两条兜底:BlockRenderer 的 `data-source-b64` 源码权威(serializer 读 b64,忽略渲染产物),以及 serializer/剪贴板/LiveConverter 各处**逐 class 枚举**跳过(`.inkwell-drag-handle` / `.inkwell-fold-toggle`)。前者覆盖不到源码权威之外的路径(Decorator 块、未来插入可编辑区域的 UI);后者每新增一种装饰物就要在每个出口补一处枚举,易漏。本契约用一个显式属性消除这类静默污染的可能性。

**契约**:带 `data-inkwell-ui` 属性的元素**及其整个子树**,对以下三条"内容出口"不可见:

| 路径 | 剥除方式 |
|------|---------|
| **Serializer** | 遍历前在**克隆副本**上剥除(`stripUIElements`),不动 live DOM |
| **剪贴板(copy/cut)** | 写入 clipboard 前对选区克隆片段剥除(同一 `stripUIElements`) |
| **LiveConverter** | 文本扫描/块识别(`getBlockSourceText`)入口处跳过带此属性的子树 |

统一剥除函数(serializer 与剪贴板共用,各自传入自己的克隆):

```javascript
// 仅在脱离文档的克隆/片段上调用——原地移除,会破坏 live UI。
function stripUIElements(root) {
  root.querySelectorAll('[data-inkwell-ui]').forEach(el => el.remove());
  return root;
}
```

LiveConverter 因其扫描机制不同,不做"克隆-剥除"而做"扫描-跳过"(遍历子节点时按同一属性略过)。三条路径共享的是**同一组被排除元素**(`[data-inkwell-ui]`),而非同一遍历策略。

**边界**:

- `data-inkwell-ui` 标记的是"**附加** UI 元素",**不用于"被装饰的内容本身"**。hljs 着色 span **不带**此属性——Decorator 产物的源码本就在 core 渲染的 `<code>` textContent 里,走既有 `<pre><code>` 文本提取路径序列化。渲染产物(mermaid SVG、stockchart 标题/画布、carousel 的图片幻灯)同理属"内容/渲染",**不打标**;只有其上的**附加控件**(edit-button、loading/error 占位、carousel 箭头/圆点/计数器)才打标。find/replace 的 `.inkwell-find-highlight` 也不打标:它包裹的是用户内容,序列化时**解包保留 inner**,而非整体剥除。
- 与 `contenteditable="false"` **正交**:前者管**序列化可见性**,后者管**编辑可达性**。UI 装饰元素通常两者都带,但二者独立——一个元素可以 CE=false 却参与序列化(被装饰内容),也可以带 `data-inkwell-ui` 而由祖先继承 CE=false(如 renderer root 内的 edit-button)。

**设计债(如实记录)**:serializer 现每次 `getMarkdown()`(每次内容变更即调)克隆整棵 `#editor`(含渲染产物 SVG/canvas)后剥除。典型文档成本可忽略(cloneNode 为原生实现,数千节点亚毫秒级);极端大文档(多张复杂 mermaid)若每键一次深克隆成瓶颈,回退方向:serializer 改为 live 遍历 + `serializeNode` 内行内跳过 `[data-inkwell-ui]`(放弃与剪贴板的**函数**共享,保留**属性**共享)。

> 本契约兑现了 `PHASE_3_5_EDITMODE.md` 附录设计债 **D2**("第二种注入 contentEditable DOM 的 UI 装饰物出现时,应升级为统一 `data-inkwell-ui` 属性过滤")。逐 class 枚举的既有跳过点(keydown/beforeinput 删除守卫、slash 菜单块文本、导出路径)不在本次"内容出口"范围内,保留原样;drag-handle/fold-toggle 现同时带 class 与属性,两套过滤并存无冲突。

### 3.5 块级删除机制(`BlockDeletion`)

结构化块(表格、carousel,未来 mermaid/stockchart 等)需要一个统一的"删除整块"操作。目标是**一处实现删除行为,块类型只声明是否提供入口**,而不是每种块各写一个删除按钮各管一套 undo。

**核心行为(core 统一实现)**:`BlockDeletion.deleteBlock(blockEl)`,`blockEl` 必须是 `#editor` 的**顶层子节点**(表格 = `<table>`;carousel = `.inkwell-block-renderer` root)。三步:

1. **原子删除**(见下"undo 契约")
2. **光标落点**:落到**前一个块的末尾**;无前块则后一个块开头;两者都无(唯一块)则由 `ensureEdgeGaps()` 新建 `<p><br></p>` 并落入。理由:删块类比"退格合并",光标停在已存在的可编辑正文里最不突兀;前块末尾一定是合法 caret 位,而相邻块可能又是 CE=false 渲染块(无 caret 位),故优先前块。删除后**显式设 selection**——设 selection 不进 undo 栈,不破坏原子性。
3. **唯一块保护**:删除后调既有 `ensureEdgeGaps()`,空文档自动补 `<p><br></p>` 并聚焦,文档始终可输入。

#### undo 契约:为什么必须走 `execCommand`(本节是后续 undo 边界设计的输入)

`PHASE_3_5_EDITMODE.md` OQ1/D1 已裁决:**不引入自管 undo,完全依赖浏览器原生 contentEditable 撤销栈**;裸 DOM 改动(`removeChild`/`replaceChild`)**不进原生撤销栈**,故 enter/leave-edit 是"不可撤销边界"。这直接约束了删除的实现:

- ❌ `blockEl.remove()` / `replaceChild` —— Cmd+Z **完全无效**,违反"单一原子 undo 步"要求。
- ✅ **把删除动作走原生编辑管线**——整块 `selectNode` 后一次 `execCommand('delete')`:

```javascript
const range = document.createRange();
range.selectNode(blockEl);            // 整块作为一个单元选中
sel.removeAllRanges(); sel.addRange(range);
document.execCommand('delete');       // 一次 execCommand = 一个 undo 单元
```

**原子性从何而来**:`execCommand` 是编辑器既有的 undo 集成路径(格式命令、cut handler L5801 均走它)。每次 `execCommand` 调用在原生撤销栈里登记**一个** undo 单元;WebKit 对被删片段做整体 DOM 快照,Cmd+Z 一次恢复整棵子树(表格全部单元格内容 / carousel 全部图片幻灯 + 控件),不拆成多步。光标落点是删除**之后**的独立 selection 操作,不产生第二个 undo 单元。

**与既有删除守卫的关系**:`beforeinput` 守卫(L5529)只在**部分切入**受保护块(`startP`/`endP` 落在 `<pre>`/renderer 内且有残留)时 `preventDefault`。整块 `selectNode` 时删除边界落在 `#editor` 层,`startP`/`endP` 均为 `null`,守卫不拦截,块被干净整体删除。`execCommand` 不触发 keydown,keydown 守卫天然无关。

> **正式先例**:自本节起,"要原子可撤销 → 必须过 `execCommand`;裸 DOM 改动一律是不可撤销边界"成为 Inkwell 的 undo 边界规则。D1 的边界清单据此扩展(见 `PHASE_3_5_EDITMODE.md`)。

#### 声明机制(块类型如何提供删除入口)

| 块类型 | 出生方式 | 声明方式 |
|--------|---------|---------|
| carousel(image-group) | 注册的 BlockRenderer | spec 增字段 `deletable: true` |
| table | core 原生 parser 产物(非 extension) | 无 spec,由 `TableManager` 直接接线 |

**不对称如实记录**:`deletable` 只对注册的 BlockRenderer 有意义;table 是 core DOM,没有 spec 承载声明,故由其菜单持有者(TableManager)直接调 `BlockDeletion`。共享的是 **core 行为**(`deleteBlock` + 删除项工厂 `createMenuItem`),而非一套配置驱动的注册表——2 个用例不足以支撑通用注册表(YAGNI)。未来第 3 种块接入时若仍是 BlockRenderer,`deletable: true` 直接复用;若是又一种 core 原生块,同 table 直接接线。

#### UI 契约

- **入口形态**:删除项是**破坏性菜单项**,加入块的浮动块菜单;与其他项视觉区分(红色调),**不做二次确认弹窗**,依赖 undo 兜底。
- **表格**:在既有 `.inkwell-table-toolbar` 尾部(分隔符后)追加"Delete Table"项。
- **carousel**:carousel 此前**没有块菜单**(只有箭头/圆点/计数器导航件)。新建一条**浮动块工具条**(仿 `.inkwell-table-toolbar` pattern),选中/hover carousel 时浮出,含 Delete 项。此工具条为**通用 renderer 块菜单**雏形:凡 `data-renderer` 对应 spec `deletable: true` 的 root 即挂载。
- **`data-inkwell-ui` 合规**:删除项及浮动菜单容器经 `createUIElement` / 打 `data-inkwell-ui` + `contenteditable="false"`,不进序列化/剪贴板(§3.4)。carousel 图片附件文件本身不受影响——删除只移除 DOM(即 .md 里的 `![]()` 引用),磁盘图片文件不动。

#### 待交互验收的实现风险(WKWebView 实机,由用户在运行 app 中确认)

| 风险 | 说明 | 兜底 |
|------|------|------|
| 相邻块合并 | `selectNode + execCommand('delete')` 删除夹在两段落间的块后,WebKit 是否把前后两段落误并成一段 | 若复现:改用 `execCommand('insertHTML', …)` 1:1 替换,或调整边界 |
| 复杂子树 undo 恢复 | 表格多单元格 / carousel 多图 的 Cmd+Z 是否逐属性完整还原 | execCommand 快照理论覆盖;实机确认 |
| 空文档 caret | 删唯一块后 WebKit 可能留 `<br>`/空 text,`ensureEdgeGaps` 的空判定需覆盖 | 实机确认后按需收紧空判定 |

#### 明确不做(本次边界)

- ❌ mermaid / stock chart / 代码块的删除接入(机制稳定后按需接;它们只需 `deletable: true` 或直接接线)
- ❌ 删除的键盘快捷键
- ❌ 二次确认弹窗
- ❌ Phase 3.5 编辑状态机改动、serializer 源码权威逻辑改动

#### 实施顺序(一个 commit)

1. Core `BlockDeletion`:`deleteBlock` + `createMenuItem` + 破坏性菜单项 CSS
2. TableManager:工具条尾部追加 Delete Table 项
3. Carousel 浮动块菜单 + image-group spec `deletable: true`
4. 回归(表格增删行列/排序、carousel 导航、find/replace、主题切换、round-trip)+ build + 交付交互验收清单

### 关于源码存储:为什么用 base64 attribute

三种方案对比后的选择:

| 方案 | 评价 |
|------|------|
| `encodeURIComponent` 入 attribute | 不是为 HTML attribute 设计的,边界 case 多 |
| `<script type="text/plain">` 子节点 | DevTools 可读,但 contentEditable 内嵌 script 行为是边界 case |
| **base64 入 attribute** ⭐ | 完全无转义问题;DOM 扁平;DevTools 需 `atob()` 解码 |

稳定性 > 调试便利性。

---

## 四、Context API

### BlockContext

```javascript
{
  // DOM 构造
  createBlockRoot({ renderer, sourceMarkdown, language, editStyle }),
  createElement(tag, attrs, ...children),
  createUIElement(tag, attrs, ...children),   // 附加 UI 件:自动带 data-inkwell-ui + contenteditable="false"

  // 状态管理
  setLoading(rootEl, message),
  setError(rootEl, errorInfo),       // errorInfo: { type, message, ...自定义 }
  replaceOutput(rootEl, newDOM),

  // 源码访问
  getSourceMarkdown(rootEl),

  // 异步任务
  runAsync(rootEl, task, { onError }),

  // 主题信息(只读)
  theme: { isDark, colors }
}
```

### `runAsync` 详细契约

```javascript
context.runAsync(root, async (signal) => {
  const output = await renderMermaid(block.content, { signal });
  if (signal.aborted) return;
  context.replaceOutput(root, output);
}, {
  onError(error, root) {              // 必填
    if (error.name === 'MermaidParseError') {
      context.setError(root, { type: 'syntax', message: error.message });
    } else {
      context.setError(root, { type: 'runtime', message: 'Render failed' });
    }
  }
})
```

**runAsync 保证**:

- 同一 root 同时只有一个 in-flight 任务,新任务自动 abort 旧任务
- AbortSignal 透传给 renderer,避免快速切换主题等场景的竞态
- 异常自动捕获,调用 onError,不污染主流程
- **onError 必填**:强制 renderer 作者思考错误 UX,避免 core 用一套通用 fallback 误处理所有错误

### `createUIElement`

与 `createElement` 同签名,额外自动附加 `data-inkwell-ui`(序列化/剪贴板不可见,见 §3.4)与 `contenteditable="false"`(编辑不可达)。扩展作者用它创建"附加 UI 件"(按钮、提示、浮层控件),无需记住 §3.4 契约:

```javascript
const btn = context.createUIElement('button', { className: 'my-action' }, 'Reload');
// → <button class="my-action" data-inkwell-ui contenteditable="false">Reload</button>
```

**约定**:core 内部创建的 UI 件(edit-button / loading / error 占位)直接加属性;**扩展内**创建的 UI 件一律走 `createUIElement`。内置 image-group(carousel)扩展的箭头/圆点/计数器是首个真实消费者。

---

## 五、占位符渲染路径

`BlockRenderer.render()` 契约要求同步返回 HTMLElement,且 runAsync 内部把 AbortController 挂在 `root.__inkwellAbortController` 上。但 Markdown parser 输出的是 HTML 字符串——若通过 `outerHTML` 序列化后再 `innerHTML = ...` 设置,所有 JS 状态(包括 AbortController)都会丢失,runAsync 失效。

**实际路径**:parser 阶段输出占位符,核心阶段扫描替换。

```
Parser 阶段:
  匹配到注册的 fenced renderer →
    输出 <div class="inkwell-pending-renderer"
              data-pending-renderer="..."
              data-pending-language="..."
              data-pending-source-b64="...">
  否则 → 输出原生 <pre><code>,留给 highlight-code Decorator 着色

loadMarkdown 阶段:
  innerHTML = parser.parse(...)
  → _resolvePendingRenderers() 扫描占位符,调 renderer.render(),
    用返回的真 HTMLElement 替换占位符(runAsync 此时正常工作)
  → BlockDecorator 装饰剩余的 <pre><code>
```

**所有 BlockRenderer 共享此路径**。未来 PR(KaTeX display math、timeline)新增的 BlockRenderer 不需要改动这部分代码。

---

## 六、重渲染调度

当 `rerenderOn: [...]` 中的 trigger 触发(如主题切换)时,core 统一执行:

```
重渲染前:
  1. 记录当前 selection (如果在文档内)
  2. 检测 IME composition 状态 —— 若在输入中,延迟到 compositionend
  3. 记录滚动位置

重渲染中:
  4. 若 renderer 有"全局状态前置"需求(如 mermaid.initialize) → 先执行
  5. 找到所有匹配的 block/decorator 节点,从 source 重新调用 render() / decorate()
  6. runAsync 自动 abort 任何 in-flight 的旧任务

重渲染后:
  7. 尝试恢复 selection
  8. 恢复滚动位置
```

Renderer 作者不需要关心主题切换或选区保护——core 统一处理。

### 已知设计债:全局状态前置

某些 renderer 有**全局状态**,触发重渲染时需要先重新初始化全局状态,再让所有实例重渲染。Mermaid 就是典型:`mermaid.initialize({ theme })` 是全局调用,影响后续所有 `mermaid.render()`——如果只重新调 `render()` 而不先 initialize,新生成的图仍是旧主题色。

**当前实现**:`_notifyRerender('theme-change')` 在派发到具体节点**之前**硬编码做 mermaid 全局重初始化。

**风险**:如果未来 KaTeX、Three.js 等扩展也有主题相关的全局状态,要么各自硬编码进 `_notifyRerender`(累积多了就会乱),要么抽出一个 hook 让 renderer 声明 `onTriggerGlobal(trigger, isDark)`。

**处理时机**:PR 3 KaTeX 实施时若发现同类需求,就是抽象这个 hook 的时机。在那之前不要预先抽象。

---

## 七、Serialize 优先级

```
保存时对每个 block:
  1. 优先读 data-source-b64 → base64 解码 → 这就是源码
  2. 如果 renderer 显式提供 serialize() 且 block 标记为可编辑 → 调用 serialize
  3. 失败兜底:尝试从 .renderer-output 提取文本
  4. 最坏情况:跳过此 block 但不破坏其他内容
```

**核心原则**:源码权威性 > renderer 智能性。Mermaid/KaTeX/timeline 这类"渲染完全由源码决定"的扩展,**根本不需要实现 serialize**,core 直接读 base64 即可。

---

## 八、错误隔离与上报

### safeCall 包装

所有 renderer 方法调用都被包一层:

```javascript
function safeCall(extensionName, method, fn, fallbackFn) {
  try {
    return fn();
  } catch (error) {
    console.error(`[Extension:${extensionName}] ${method} failed`, error);
    reportToSwift({ extension: extensionName, method, error: String(error) });
    return fallbackFn?.(error);
  }
}
```

### 故障行为表

| 阶段 | 失败处理 |
|------|---------|
| `match` 抛错 | 跳过此扩展,继续尝试下一个 |
| `render` / `decorate` 抛错(同步) | 渲染为 error fallback,保留源码 |
| `runAsync` 任务抛错 | 调用 renderer 的 `onError`,loading 占位被替换为错误 UI |
| `serialize` 抛错 | 回退到 base64 解码的源码 |
| **任何阶段** | **源码绝不丢失(底线)** |

### Swift 侧错误上报

`MarkdownEditorView.swift` 中已落地的 message handler:

```swift
case "extensionError":
  if let dict = message.body as? [String: Any] {
    print("⚠️ [Extension] \(dict)")
    // 未来可加:弹 toast、写日志文件、上报统计
  }
```

---

## 九、Registry 公开接口

```javascript
const ExtensionRegistry = {
  // 注册
  registerBlock(spec),
  registerBlockDecorator(spec),
  registerInline(spec),

  // 查询(core 使用)
  findBlockRenderer(block),
  findBlockDecorators(el),
  matchInline(text),

  // 渲染(core 使用,带 safeCall)
  renderBlock(block),
  decorateBlock(el),
  renderInline(match, renderer),

  // 序列化(core 使用)
  serializeNode(node),

  // 调试
  list(),
  isEnabled(name)
};
```

### 故意不提供

- ❌ `enable/disable` 运行时开关
- ❌ `unregister` 卸载
- ❌ `EmbedRegistry` 独立类型(用 `capabilities` 表达)
- ❌ 扩展依赖声明、版本检查
- ❌ 第三方加载机制

---

## 十、WebAssets 资产层

部分扩展依赖外部 JS 库(如 mermaid.min.js 约 3MB),不能内联进 editor.html,不能让用户文档目录被污染,也不能用 `loadFileURL(_:allowingReadAccessTo:)` 跨多目录读。

**方案**:自定义 URL scheme `inkwell-asset://` 配合 `WKURLSchemeHandler`,从 app Bundle 内的 `WebAssets/` 文件夹读资产。

editor.html 引用方式:

```html
<script src="inkwell-asset:///mermaid.min.js"></script>
```

**实现**:

| 文件 | 角色 |
|------|------|
| `Inkwell/Editor/InkwellAssetSchemeHandler.swift` | scheme handler 实现(约 140 行) |
| `Inkwell/Resources/WebAssets/` | folder reference,资产文件丢进去自动包含 |
| `MarkdownEditorView.createWebView` | 注册 scheme handler |

**特性**:

- 资产跟随 app 二进制——用户更新 app 自动更新版本
- 零文件复制 IO
- `Cache-Control: public, max-age=31536000, immutable`(资产跟 app 走,可长缓存)
- 拒绝 `..` 路径穿越(防御性编程)
- 所有未来扩展(KaTeX、未来 Three.js 等)共用此层

详见 `docs/WEBASSETS.md`。

### highlight.js 本地化(2026-07-16)

Phase 3 期间 highlight.js 的 **JS 本体与深浅两套主题 CSS 一直是 cdnjs 活外链**(`<link id="hljs-theme">` + `<script>`,pin 在 11.11.1),`updateDarkModeTheme()` 还会把 `#hljs-theme` 的 href 改写到另一个 cdnjs 地址。这是零外部依赖底线的破口,且断网时代码高亮完全无样式。

修复:三个文件 vendored 进 `WebAssets/highlight/`,经 `inkwell-asset:///highlight/` 加载,与 mermaid/katex/lightweight-charts 同一模式;`updateDarkModeTheme()` 的 base 改为 `inkwell-asset:///highlight/`,深浅切换在两个本地 CSS 间进行。版本严格沿用原 pin 的 11.11.1(文件内 `versionString="11.11.1"` 已核对),只改交付方式不改版本。三个文件自包含:CSS 无 `url()`/`@import`,JS 无网络请求。**至此 editor.html 无任何活外部引用**(残留的 https 字符串均为代码注释与 URL 输入框 placeholder)。

命名位注意:synchronized groups 把子目录平铺进 Bundle 资源根,`github.min.css` / `github-dark.min.css` / `highlight.min.js` 靠 handler 的 basename fallback 命中——与 `katex.min.css` 同一条路径,无新机制。

---

## 十一、与图片附件系统的关系

两者不冲突,处于不同抽象层级:

| | 图片附件 | Mermaid/KaTeX 源码 |
|---|---|---|
| 性质 | 用户资产 | 渲染输入 |
| 存储位置 | 磁盘文件(per-note `<basename>/` 文件夹) | 永远在 .md 文件内(fenced block) |
| Markdown 表示 | `![](<basename>/foo-a1b2c3d4.png)` | ` ```mermaid ... ``` ` |
| DOM 表示 | `<img src="<basename>/foo-a1b2c3d4.png">` | `<div data-source-b64="..."><svg>...</svg></div>` |
| base64 涉及 | ❌ 不涉及 | ✅ DOM 内部临时形态 |

**关键点**:base64 attribute 只是 DOM 内部状态,**保存到磁盘的 .md 文件里没有任何 base64**——磁盘上永远是干净的 fenced markdown。图片资产放在与笔记同级的 `<basename>/` 文件夹里(笔记 `foo.md` → `foo/`),markdown 用相对路径 `<basename>/<file>` 引用,解析基准是笔记所在目录(与下方 readLocalFile 读取边界同一目录)。

### 图片附件写入:per-note 文件夹 + 共用写入逻辑(`InkwellAttachmentStore`)

笔记 `<basename>.md` 的关联资产统一写入同级 `<basename>/` 文件夹。此**写入路径**的单一实现是 `Editor/InkwellAttachmentStore.swift`(Foundation-only、可单测,是读侧 `InkwellFileReadResolver` 的写侧姊妹)。两处调用者共享它,均不自己拼目录或起名:

- `MarkdownDocument.saveAttachment`(model 层 API);
- `EditorCoordinator` 的图片拷贝路径(carousel 与单图插入共用同一函数 `storePickedImage`)。

> **背景更正(如实记录)**:本次接入前,`saveAttachment` 里已有 `<basename>/` 逻辑但**无人调用**,真正的图片拷贝路径(`sendImageURLToJS` / iOS picker)直接写到笔记所在目录并只引用裸文件名,污染笔记目录——这正是 Part 3 修的 bug。stock chart 并不写盘,它只经 `InkwellFileReadResolver` 按笔记目录**读** CSV;故"两边共用"实际收敛的是上面两个**写**入口,读侧另有其姊妹 resolver。carousel 与单图插入共用 `sendImageURLToJS`,同一根因同一修复,单图插入一并受益。

**目录创建**:写入前 `ensureDirectory` 按需创建 `<basename>/`(已存在则复用,幂等)。

**文件名冲突** → `<cleaned>-<shorthash>.<ext>`:

- `cleaned`:保留 Unicode 字母/数字(中文、带音标名存活)+ `-`/`_`;空格、路径分隔符、文件系统/URL 敌意字符(`: ? * " < > | #` …)一律替换为 `-`;连续 `-` 折叠为一个;首尾 `-`/`_` 去除;截断到 40 字符;清理后为空则退化为 `image`。
- `ext`:小写、仅字母数字、截断到 10 字符。
- `shorthash`:内容 SHA-256 前 4 字节(8 位十六进制)。**内容寻址**:同名但**内容不同**的两个文件 → 哈希不同 → 落成两个文件;**同一份字节**插入两次 → 同名 → 复用既有文件(去重,两处引用指向同一文件)。

**未保存笔记边界**:笔记无 URL/basename 时无法派生 `<basename>/`。当前架构下每个打开的文档都已有 URL(新建笔记在编辑前即以 `Untitled N.md` 落盘),故此路不可达;代码仍防御性守卫——`documentURL == nil` 时**不插入**图片并弹原生提示(macOS `NSAlert` / iOS `UIAlertController`),而非静默污染或静默失败。

**删除语义**:删除 carousel 块(见 §3.5)**只移除 markdown 里的 `![]()` 引用,不删除磁盘图片文件**。理由:用户可能仅调整版式(删了重排),不应连带毁掉资产;由此产生的孤儿图片文件交由未来的"整理附件"命令处理(见 roadmap)。本次也**不迁移**已散落在笔记目录里的旧图片——同属整理命令范畴。

### readLocalFile 文件读取边界(D.15 修订版,2026-07-16)

`window.inkwell.readLocalFile(relativePath)` 桥(现用户:stockchart 本地 CSV)的 Swift 侧边界检查由 `InkwellFileReadResolver` 执行。**基准从笔记文件名改为笔记所在目录**:

1. 拒绝绝对路径(错误码 `invalidFilePrefix`,rawValue 与 JS 契约保持不变)
2. 相对路径对笔记所在目录解析并规范化(`standardizedFileURL`)
3. 规范化结果必须严格位于笔记所在目录内部——带尾斜杠前缀比较,空路径、`.`、任何 `../` 逃逸一律拒绝(错误码 `outsideAttachmentDir`)
4. 包含检查对**符号链接解析后的真实路径**执行(基准与候选两侧同管线),返回值即解析后路径,读取与检查命中同一目标。目录内符号链接照常工作;指向目录外的符号链接(文件或文件夹)被拒——防止恶意 vault 借链接把读取走私出边界(2026-07-16 补)

初版契约(已废止)要求路径以 `<docname>/` 开头且解析后留在同名附件目录内。废止原因:(a) 笔记 rename 后 `<docname>` 变化而正文引用不变,CSV 引用必断,而图片通道(WebView base URL = 笔记所在目录,`allowingReadAccessTo` 同样是目录)不受影响——两通道不对称,且 resolver 单方面收紧不构成真实安全边界:任何 `<img>` 早已能读同目录任意文件;(b) `<docname>` 派生逻辑对点开头文件名(`.md`)有未定义行为。目录基准下两通道对称、rename 天然安全(同目录改名不改目录,连 coordinator 持陈旧 documentURL 的 live session 也正确)。副作用如实记录:跨笔记引用(`other-note/AAPL.csv`)从被拒变为允许,与图片通道行为一致;per-note 隔离由此让位于 per-directory 隔离,真实安全边界(不出笔记目录、防穿越、拒绝绝对路径)强度不变。

---

## 十二、已知限制

### round-trip 事故清单(2026-07-16 发现,逐条待办)

在 `tests/katex-smoke.md` / `tests/mermaid-smoke.md` 的磁盘副本上发现五类 round-trip 损坏,**直接违反底线 1(磁盘产物必须是干净标准 Markdown)**。发现时间 7/16,损坏发生在 7/13–7/14,与 Phase 4 各 PR 无关。

| # | 症状 | 状态 |
|---|---|---|
| 1 | 无语言 ``` 围栏存盘后被塞进 hljs 猜的语言(```ruby / ```lua / ```kotlin) | **已修**(2026-07-16,decorator 剥离探测结果;见附录 A 决策记录)。测试网守卫 `testFenceWithoutLanguage` |
| 2 | `<span style="color:rgb(...)">` 裸 HTML 落盘 | **当前代码不复现**(见下「侦查结论」)。纯 round-trip 路径干净(`testCodeThenHeading` 绿) |
| 3 | `## 1. Flowchart` → `## Flowchart`,标题编号被吃 | **当前代码不复现**(纯/多轮/交互三路径均干净;`testHeadingNumbered` 绿) |
| 4 | `PHASE_3_ARCHITECTURE` → `PHASE*3*ARCHITECTURE`,词内下划线被当斜体 | **已修**(2026-07-16,Step 2:下划线 emphasis 加词边界守卫)。测试网 `testEmphasisUnderscore` |
| 5 | `---` 分隔线 → 空表格 | **已修**(2026-07-16,Step 2:表头必须含 `\|`,阻止空行被当表头)。测试网 `testThematicBreak` |

测试网新捕获(超出原五类,均可在纯 round-trip 复现):

| # | 症状 | 状态 |
|---|---|---|
| 6 | 嵌套/缩进列表项之间被增删空行(tight↔loose 漂移) | **已修**(2026-07-17,parseList 递归嵌套 + serializeList 按 marker 宽度缩进;方案 C)。测试网 `testNestedList` / `testNestedListOrdered` / `testListSiblings` |
| 7 | 软换行段落(相邻两行无空行)被拆成两段 | **已修**(2026-07-17,段落模型 PR:parser 段内合行 + Shift+Enter 硬换行 `<br>`↔`\`)。见下「#7 段落模型」 |
| 8 | 表格列对齐一律塌成居中(`:---` / `---` → `:---:`) | **已修**(2026-07-17,serializeTable 无 inline align 的列输出 `---` 而非 `:---:`)。测试网 `testTableAlignment` |

行内 emphasis 标记规范化:真 `_emphasis_` → `*emphasis*`(标记风格统一,语义不变)。已由金标断言锚定(`testEmphasisMarkerNormalization`),论证见 `tests/roundtrip/NORMALIZATION.md`。

### #7 侦查结论(2026-07-17,只侦查不修)

**拆分位置:parse。** `MarkdownParser.parse` 对每一非空行单独产出一个 `<p>`(editor.html「html += '<p>' + parseInline(line) + '</p>'」一行一段)。相邻两行(无空行)因此在 parse 阶段就成为**两个独立 `<p>`**。

**DOM 留痕:无。** 实测 `line one\nline two` → DOM 为 `<p>line one</p><p>line two</p>`,`<br>` 数为 0,无合并 `<p>`。软换行不留任何痕迹;serialize 只是忠实渲染 parser 造出的两段(每个 `<p>` → `\n\n`),所以磁盘上多一个空行。硬换行(尾双空格)同样被拆成两段,尾空格留存但 `<br>` 语义丢失。

**同根实例**:`intro:\n- item`(段落紧跟列表,无空行)→ `<p>` + `<ul>` 两块 → serialize 插空行。这就是 `smoke-katex` 现存的唯一残留(`testSmokeKatex` 的 xfail 理由),与 #7 同根。

**设计裁决点(留给设计侧)**:
- 方案「段内合行」:parser 累积连续非空行为**单个** `<p>`(软换行以空格或 `<br>` 表示),贴合 CommonMark 段落语义,round-trip 可做到 byte-exact。
- 方案「维持拆段」(现状):每行一段,改变渲染语义(一段变两段视觉块),round-trip 插空行。

**张力**:Inkwell 是 WYSIWYG——Enter 通常意味着新段落,Shift+Enter 才是段内换行。若 parser 把 `line1\nline2` 合成一段,与「Enter=新段」的编辑模型可能冲突。这是渲染语义(CommonMark)与编辑 UX(WYSIWYG per-line 段落)之间的真实取舍,须设计侧定夺,本程不改。

### #7 段落模型(2026-07-17,已裁决并实现)

裁决采「段内合行」(贴合 CommonMark),而非维持拆段。实现:

- **Parser**:连续非空非块级行归入同一 `<p>`(`_startsBlock` 判块界);软换行折为空格,硬换行(行尾 `\` 或两尾空格)成 `<br>`。
- **Enter / Shift+Enter**:Enter 仍是新段落(原生);Shift+Enter 显式拦截插确定性 `<br>`,`!isComposing` 守卫(IME 组合期间不拆);光标落 `<br>` 之后。
- **序列化**:`<br>`↔ 行尾 `\`(规范硬换行);但空段落占位 `<p><br></p>` 的 `<br>`(后无内容)不输出 `\`,避免边缘占位符渗出杂散反斜杠。
- **规范化**(白名单 + 金标,见 `tests/roundtrip/NORMALIZATION.md`):软换行折为一行(位置丢失);块间无空行→空行分隔;两尾空格→`\`。smoke-katex/-mermaid 配 `.expected.md` 金标转绿。

**既有文档渲染观感变化(用户须知)**:此前用软换行写作的 `.md`,每行显示为独立小段(带段间距);改后连续软换行行**合为一个随宽度重排的段落**(无段间距),与 GitHub/Typora 对软换行的渲染一致,是修正非退化。明确的 Shift+Enter / 行尾 `\` 硬换行保留为 `<br>`,不受影响。折叠发生在**加载时**,首次保存即写回折叠形态(段落一行);用户若要保留换行须改用硬换行——这是一次性规范化迁移。

### 侦查结论(2026-07-16,Step 3)

事故 #2(span 泄漏)、#3(标题编号被吃)、以及 mermaid-smoke.md 的 ```mermaid → ```less 未知出口:**在当前 editor.html 上,纯 round-trip、5 轮多轮 round-trip、以及 enter/leave-edit 交互循环三条路径全部无法复现**。

- ```mermaid → ```less 属事故 #1(语言捏造)同族——可复现的那半已修;标签丢失不复现。
- 磁盘证据:`## ​1. Flowchart` → `## ​ Flowchart`(仅 `1.` 被吃,零宽空格前缀留存)、`## 6. Pie Chart` → 标题里**并入饼图代码内容** `"WebAssets 抽象" : 30` 加 hljs 颜色 span。后者是 DOM 合并式损坏,非纯序列化产物。
- 时间线:坏文件工作区 mtime 为 7/13,editor.html 其后经历大量修复。

**判定**:#2/#3 及 mermaid 出口要么已被其后的修复消解,要么源自测试网不覆盖的交互编辑路径。当前无 live 复现,依「找不到如实报告」不盲修。若日后重现,证据指向交互编辑(contentEditable 块合并),而非 parser/serializer 纯路径。

### 标题吞并(#2/#3)已在交互路径定位并修复(2026-07-17,Step 5)

Step 3 的判定得到证实:标题吞并**就住在交互编辑路径**,纯 round-trip 够不到。交互网(`InkwellTests/InteractiveEditTests` + `INTERACTIVE_PLAN.md`)建成后**确定性复现**:

- **边界 forward-delete**:标题/段落尾按 Delete、下一块是渲染代码块 → WebKit 把代码文本化合并进标题,hljs 颜色以 inline `<span style="color:...">` 泄漏落盘(正是磁盘上 `## 6. Pie Chart<span style=…>` 的活体)。编辑器此前**对 Delete 键零守卫**。
- **跨块选区部分切入**:选区从文本块跨入代码块中部删除,残余代码文本化并入前块。

两者已修(keydown Delete 守卫 + 跨块部分切入守卫,方案 A),经 keydown `defaultPrevented` 验证(execCommand 绕过 keydown/beforeinput,不能验证守卫——见 INTERACTIVE_PLAN 实施记录)。#2(span 泄漏)与 #3(标题编号被吃)同属此路径的产物:span 泄漏即上述颜色泄漏;编号被吃是合并时标题前缀文本受损。渲染块(mermaid/math div)不文本化,天然免疫。

复现手段:`scratchpad/harness` —— 取真实 editor.html,仅把 `inkwell-asset:///` 改写为 http 路径,其余一字不动,在浏览器里跑 `InkwellEditor.loadMarkdown()` → `getMarkdown()` 对比。快速迭代用;正式回归以 `InkwellTests/RoundTripTests`(离屏 WKWebView + 真 Bundle 资产)为准。

**测试网已补齐**:`tests/roundtrip/` + `InkwellTests/RoundTripTests` 是常驻交付物,经 `xcodebuild test` 运行,覆盖上述纯 round-trip 路径。交互编辑路径的自动化仍是缺口。

### LiveConverter 实时切换未接入

设计区分了两条渲染路径,实际只接通了一条:

| 路径 | 触发场景 | 是否走 BlockRenderer |
|------|---------|------|
| Parser 路径 | loadMarkdown / 冷启动加载 | ✅ 已接入 |
| LiveConverter 路径 | 用户实时输入 ` ```mermaid ` | ❌ 仍生成原始 `<pre><code>` |

**当前用户体验**:在编辑器里现场敲 mermaid 块,必须重新加载文件才能看到渲染产物。代码里加了 TODO 注释。

**为什么不解决**:实时切换涉及 typora-style edit-mode 的设计议题——光标进入 mermaid 块时显示什么(源码?渲染图?)、切换时机、UX 取舍,都不简单。是独立话题,留待未来专项处理。

---

## 十三、路线图(精简版)

### 已完成

- **PR 1**:ExtensionRegistry + BlockRenderer/BlockDecorator/InlineRenderer 三类骨架 + 迁移 highlight.js (→ `highlight-code`) + 迁移 `==text==` (→ `highlight-mark`)
- **PR 2**:Mermaid 接入,确认架构在异步渲染、错误语义、主题响应、AbortSignal 防竞态全部场景下成立;附带产出 WebAssets 资产层

### 下一步

**PR 3 — KaTeX Display Math (`$$...$$`)**

- 复用 PR 2 验证过的异步渲染模式(BlockRenderer + runAsync)
- 注册新 block 类型 `math-block`(不是 fenced-code,需要 parser 适配)
- KaTeX 库通过 WebAssets 层引入(`inkwell-asset:///katex.min.js`)
- 实施前提醒:
  1. **不要预先抽象 renderer 全局状态 hook**——等 KaTeX 真的需要时再抽(见第六节"已知设计债")
  2. 占位符路径已通用,KaTeX display math 直接套(见第五节)
  3. WebAssets 已就位,KaTeX 库丢进 `WebAssets/` 即可(见第十节)
  4. InlineRegistry v1 不能做 KaTeX inline——这条限制不要破例
  5. KaTeX 渲染本身是同步的,但仍要走 BlockRenderer 接口(产生 `data-source-b64` 包裹)

### 后续

- **PR 4 — Timeline**:` ```timeline ` fenced block,纯 SVG 自绘,验证"完全本地无网络"扩展形态
- **PR 5 — Inline Parser v2**(future scope):当 KaTeX inline / 复杂 mention / 自定义 directive 需要 parser-aware 扩展点时启动,需独立设计议题
- **PR 6 — Stock Chart / 网络数据扩展**(future scope):新增 `capabilities.network`、`refresh`、`cache`,可能此时拆出独立的 `EmbedRenderer` 类型

### 明确不做(Phase 3 范围外)

- ❌ 运行时启用/禁用扩展
- ❌ 用户级第三方插件加载
- ❌ 扩展配置 UI 自动生成
- ❌ iframe / Worker 沙箱隔离
- ❌ build-time 文件拆分
- ❌ 扩展依赖管理 / 版本检查
- ❌ 扩展热重载

这些都是"插件平台"特征。Inkwell 是本地编辑器,不是插件平台。**接口为它们留了位置但不为它们工作**。

---

## 附录 A:决策记录

| 决策 | 选择 | 原因 |
|------|------|------|
| 物理文件结构 | 单文件(editor.html 内置一切) | 避免异步注入、Bundle 管理、跨文件调试的复杂度 |
| 扩展类型 | Block + BlockDecorator + 受限 Inline(三类) | highlight.js 不接管 DOM 所有权,语义上不是 Renderer |
| 源码存储 | base64 in attribute | 无转义问题;contentEditable 兼容性好;DOM 扁平 |
| 异步渲染 | render 同步返回 + runAsync | JavaScript 语义清晰;编辑器主流程同步 |
| 错误处理 | onError 必填 | 强制 renderer 思考错误 UX 差异(语法错 vs 运行时错) |
| 重渲染触发 | 声明式 `rerenderOn: [...]` | 避免内存泄漏;core 统一处理 selection/IME/scroll |
| 主题切换防竞态 | runAsync 内置 AbortSignal + 自动取消旧任务 | 减少 renderer 作者负担 |
| 全局状态前置 | 暂硬编码,不预先抽象 hook | 仅 mermaid 一例,YAGNI |
| 大型 JS 库管理 | 自定义 `inkwell-asset://` scheme + Bundle | 不污染用户目录;跟随 app 版本;零复制 IO |
| readLocalFile 边界基准(2026-07-16 修订) | 笔记所在目录(见 §十一 D.15 修订版) | 初版 `<docname>/` 前缀在 rename 后必断且与图片通道不对称;目录基准下两通道同一边界,穿越防护强度不变 |
| 围栏语言的权威来源(2026-07-16) | 作者声明的语言;hljs 的自动探测**仅供显示**,不得进入序列化 | 与「源码权威性」同源:探测结果一旦留在 DOM 的 `language-*` class 上,serializer 会把它当成用户写的语言存盘——无语言围栏存盘后变 ```ruby,即捏造源码 |
| UI 装饰排除机制(2026-07-20) | `data-inkwell-ui` 属性 + 统一 `stripUIElements`(serializer/剪贴板)+ 扫描跳过(LiveConverter);见 §3.4 | 逐 class 枚举覆盖不到源码权威之外的路径(Decorator 块、未来可编辑区域 UI),且每新增装饰物需补多处;显式属性契约消除静默污染,兑现 3.5 设计债 D2 |

---

## 附录 B:术语表

- **BlockRenderer**:接管整个块级结构渲染的扩展(fenced code block、math block 等)
- **BlockDecorator**:不接管 DOM 所有权,在 core 已渲染的 DOM 上装饰的扩展(语法高亮)
- **InlineRenderer**:处理行内文本片段的扩展(==highlight==、未来的 mention 等)
- **DOM Contract**:渲染产物必须遵守的 HTML 结构规范
- **Source Authority**:保存时以 base64 源码为权威,而非 `renderer.serialize()`
- **rerenderOn**:声明式的重渲染触发器配置
- **AbortSignal**:浏览器原生 API,runAsync 内部使用以防止竞态
- **safeCall**:包裹所有 renderer 方法调用的错误隔离层
- **占位符路径**:parser 输出 `inkwell-pending-renderer` div,加载后由 `_resolvePendingRenderers()` 替换为真 DOM
- **`data-inkwell-ui`**:标记"附加 UI 元素"的属性,其子树对 serializer / 剪贴板 / LiveConverter 三条内容出口不可见(§3.4)
- **`stripUIElements`**:在克隆副本/选区片段上原地移除全部 `[data-inkwell-ui]` 子树的共享函数,serializer 与剪贴板共用

---

## 附录 C:文件清单

| 文件 | 角色 |
|------|------|
| `Inkwell/Resources/editor.html` | ExtensionRegistry + 三个内置扩展注册 + parser/serializer/LiveConverter |
| `Inkwell/Editor/MarkdownEditorView.swift` | extensionError channel + scheme handler 注册 |
| `Inkwell/Editor/InkwellAssetSchemeHandler.swift` | `inkwell-asset://` 服务实现 |
| `Inkwell/Resources/WebAssets/mermaid.min.js` | Mermaid 库 |
| `Inkwell/Resources/WebAssets/highlight/` | highlight.js 11.11.1 + github / github-dark 主题 CSS(2026-07-16 本地化) |
| `Inkwell/Resources/WebAssets/manifest.json` | 资产版本台账 |
| `docs/WEBASSETS.md` | 资产管理流程文档 |
| `tests/mermaid-smoke.md` | Mermaid 烟雾测试 |

---

*Document version: 2.1 — 增补 UI 装饰排除契约(`data-inkwell-ui`,§3.4);v2.0 整合实施现实,删除过期路线图细节*
