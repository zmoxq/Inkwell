# CLAUDE.md — Inkwell 项目工作约束

> 本文件定义在此仓库工作时必须遵守的原则。它们来自 Phase 2–3 的实际教训,不是形式条款。

## 项目是什么

Inkwell:原生 macOS/iOS WYSIWYG Markdown 编辑器(Typora 风格)。SwiftUI 外壳 + WKWebView 编辑核心(`editor.html`),自研 JS parser/serializer,Swift↔JS 经 `WKScriptMessageHandler` 通信。

**定位**:原生 + Typora 级 WYSIWYG + 磁盘纯净 .md + 开放 sidecar AI 契约。护城河是架构契约,不是功能数量。

## 动手之前必读

按序阅读,理解当前状态再写任何代码:

1. `INKWELL_ROADMAP.md` — 顶层框架与 Phase 排序
2. `PHASE_3_ARCHITECTURE.md`(v2.0)— 扩展架构现状,附录里的实施现实与正文同等重要
3. `PHASE_3_5_EDITMODE.md` — 当前活跃任务的设计定稿

## 不可违背的底线

1. **源码权威性**:任何改动、任何故障,都不得破坏 `.md` round-trip。保存产物永远是干净的标准 Markdown——磁盘上没有 base64、没有 HTML 残留、没有元数据注入。
2. **零外部依赖**:不引入 npm、不引入 Swift Package、不引入 build step。JS 库只能以 vendored 文件进 `WebAssets/`,经 `inkwell-asset://` 加载。
3. **editor.html 保持单文件**:不拆分、不模块化改造。区段注释组织。
4. **不预先抽象**:hook、通用机制等第二个真实用例出现时再抽。一个用例就硬编码,并在架构文档附录如实记录为设计债。

## 工作方式

- **设计先行**:凡属设计层面的改动(接口、契约、状态机、DOM 结构),先在对应 Phase 文档中定稿,再写代码。文档没有的设计不写进代码。
- **决策确认**:遇到有多个合理方案的选择,停下来,以带标签的选项(方案 A / 方案 B)+ 各自 tradeoff 呈现,等用户明确选定("选A"/"走方案B")后再实施。不要替用户做架构决策。
- **范围纪律**:实施中发现的相邻 bug、顺手可改的问题——**不改**。记录下来,单独开 issue/commit,由用户决定何时处理。一个 PR 只做它声明的事。
- **小步提交**:按设计文档的实施顺序,一步一个 commit,每步 `xcodebuild` 验证编译通过。commit message 引用文档章节号。
- **如实记录**:实施与设计不符时,不静默偏离——改动写进对应文档的实施记录附录,差异本身有价值。
- **回归优先**:改动 parser/serializer/LiveConverter 任何一处后,现有功能(代码高亮、mermaid、math、stockchart、carousel、find/replace、主题切换)必须逐项确认无退化。

## 当前任务:Phase 3.5-A

任务书:`PHASE_3_5_EDITMODE.md`。要点:

- 严格按第八节的七步实施顺序推进,一步一 commit,不跳步不合并步
- 第十节的三个 Open Questions(undo 机制、selectionchange 形态、空段落策略)必须先对照现有代码给出答案、经用户确认,再开始第 1 步
- 交互性验收(IME、光标行为、快速进出压测)由用户在运行中的 app 里人工执行;每完成一步,明确列出该步需要人工验证的项目,等验证结果再进下一步
- leave-edit 路径直调 `renderer.render()`,**不走占位符**(占位符仅属 parser 字符串路径)
- 状态转换触发一律经 `requestEnterEdit`/`requestLeaveEdit` intent,不在事件 handler 里直接操作状态

## 明确不做(Future Scope)

运行时扩展开关、第三方插件加载、沙箱、build-time 拆分、扩展热重载、编辑态语法高亮、双栏预览。接口为它们留位置,但不为它们写代码。

## 沟通语言

- 与用户对话:中文,技术术语保持英文原文(renderer、serializer、intent 等)
- 代码注释、commit message、代码内标识符:英文
- 设计文档(*.md):中文
