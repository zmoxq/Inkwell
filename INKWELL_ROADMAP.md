# Inkwell — 项目总体路线图

> **Status**: 顶层框架文档,与 `PHASE_3_ARCHITECTURE.md` 平级
> **Document Version**: 1.0
> **Last Updated**: 2026-07-06
> **适用范围**: Phase 3 之后的全部规划;各 Phase 启动时另立专属架构文档

---

## 〇、定位声明(为什么做这些事)

Inkwell 在市场上占据的组合位置:

> **原生 SwiftUI + Typora 级 WYSIWYG + 磁盘纯净 .md + 开放 sidecar AI 契约**

2026 年中的竞争格局验证了这个组合是空位:

| 竞品 | 缺什么 |
|------|--------|
| Typora | Electron;无 AI 路线;无扩展生态 |
| Bear | 数据库囚笼,非文件;AI 是功能不是架构 |
| Obsidian | 非 WYSIWYG;非原生;AI 靠插件拼装 |
| MarkText | 已弃维护(2022 起) |
| MarkEdit | 主动放弃 WYSIWYG(源码编辑器) |
| Apple Notes | 非 Markdown 文件;封闭 |

**护城河判断**:AI 摘要/自动标签正在商品化(Bear、Apple Intelligence 均已内置)。Inkwell 的护城河不是 AI 功能本身,而是——

1. AI 产出写入 sidecar `.json`,**永不污染 `.md`**
2. 完全本地优先
3. sidecar 契约**开放、可被其他工具消费**

---

## 一、Phase 总览

```
Phase 3    扩展架构            ✅ 完成(PR 1–4',文档 v2.0)
Phase 3.5  编辑体验补完        ← 当前。LiveConverter 实时渲染是核心
Phase 4    Sidecar 元数据契约   设计可与 3.5 并行,实现在 3.5 之后
Phase 5    iOS / iPadOS 适配   提前到 AI 工具之前(付费触发点)
Phase 6    AI 组织工具         独立应用,消费 sidecar 契约
Backlog    不阻塞主线的一切
```

**排序原则**:编辑器体验是产品的地基,与 Typora 正面对标的核心体验没补完之前,不扩展新能力面。

---

## 二、Phase 3.5 — 编辑体验补完

**目标**:消除"WYSIWYG 编辑器却要重载文件才能看到渲染"这一体验硬伤,并清偿已识别的编辑器侧技术债。

### 3.5-A LiveConverter × BlockRenderer 实时接入 ⭐ 核心

现状:用户现场输入 ` ```mermaid ` 时 LiveConverter 直接生成 `<pre><code>`,不走 BlockRenderer;必须重载文件才能看到渲染产物(Phase 3 附录 C.3 遗留的 TODO)。

要解决的不只是"接一条管道",而是 **typora-style edit-mode 状态机**:

- 渲染态 ↔ 源码编辑态 的双态转换
- 光标进入/离开渲染块的触发语义
- selection 保存恢复、IME composition 保护(复用 Phase 3 重渲染调度的既有保护逻辑)
- `editStyle: "typora" | "edit-button"` 两种契约的完整落地(DOM Contract 早已预留,现在兑现)

启动时另立设计文档:`PHASE_3_5_EDITMODE.md`。

### 3.5-B Carousel 迁移为 BlockRenderer

Phase 3 已识别:carousel 是唯一值得迁移进 ExtensionRegistry 的前扩展时代功能。迁移后编辑器内不再存在"registry 之外的块级渲染物",serializer 逻辑收敛。

### 3.5-C Inline parser 消毒收尾

已建 issue 的四个 sanitization 缺口(image alt / link text / link href / 段落内裸 HTML)。安全性质的债,不该拖过 Phase 3.5。

### 验收标准(Phase 3.5 整体)

- 现场输入任意已注册 fenced block(mermaid / math / stockchart)→ 光标离开即渲染,无需重载
- 光标进入渲染块 → 按 editStyle 契约行为正确;编辑后离开 → 重渲染;Esc/失焦语义明确
- 中文 IME 输入过程中触发任何转换均不撕裂 composition
- carousel 保存往返(round-trip)与迁移前逐字节一致
- 四个消毒缺口的攻击样例全部渲染为惰性文本

---

## 三、Phase 4 — Sidecar 元数据契约

**目标**:定稿 `.json` sidecar schema,作为 Inkwell 与未来 AI 工具之间的共享契约。**这是产品护城河的载体,设计质量优先于速度。**

### 已定的设计前提

- 三层结构:`system` / `ai` / `user` + `schemaVersion`
- 不用 YAML frontmatter,`.md` 保持纯净
- inline `#tag` 语法决策在本 Phase 内做出

### 本 Phase 要新增的约束(来自竞品研究)

1. **Obsidian vault 无害兼容**:sidecar 的命名与位置必须让笔记目录被 Obsidian 当 vault 打开时完全透明(不产生噪音条目、不被误索引)。用户零迁移成本 = 获客路径。
2. **契约即文档**:schema 以公开规范的标准撰写(字段语义、版本演进规则、未知字段容忍策略),按"将来会有第三方实现"的假设来写。
3. **写入者仲裁**:`ai` 层与 `user` 层的冲突规则(用户改动永远赢?AI 建议进暂存区?)必须在 schema 层面定义,不留给应用逻辑临时发挥。

### 交付物

- `SIDECAR_SPEC.md`(公开规范级)
- Inkwell 侧读写实现 + 损坏 sidecar 的容错策略(sidecar 损坏绝不影响 .md 打开)
- inline `#tag` 决策记录

**时序**:schema 设计与 Phase 3.5 实施并行推进(纯设计工作);Inkwell 侧实现等 3.5 落地后开始。

---

## 四、Phase 5 — iOS / iPadOS 适配

**目标**:Apple 双端可用。Bear/Ulysses 证明双端是这个用户群的付费触发点,且"原生 + WYSIWYG + iOS"目前市场无人做到。

关键议题(启动时展开):

- WKWebView 编辑核心的触控适配:选区手柄、软键盘 accessory bar(替代桌面工具栏)、光标进出渲染块的触控语义(3.5 的状态机要预留触控路径)
- 文件体系:iCloud Drive / Files app 集成,替代 macOS 侧边栏文件树的交互模型
- UI 色彩一致性改进(此前已识别)合并进本 Phase 一起做

**依赖**:Phase 3.5 的 edit-mode 状态机设计时,触发语义要抽象为"意图"(enter-edit / leave-edit)而非绑死鼠标事件——这是 3.5 给 5 留的接口。

---

## 五、Phase 6 — AI 组织工具(独立应用)

**目标**:消费 sidecar 契约的第一个外部工具:碎片笔记的摘要、打标、关键段落检索。

方向性决策(现在定原则,启动时定细节):

- **双引擎**:云 API + 本地模型(Apple Intelligence / Ollama)。本地推理选项是 local-first 人群的信任信号,哪怕效果打折也要有。
- **AI 只写 `ai` 层**,永不触碰 `user` 层与 `.md` 本体——这是对外宣传的核心承诺,架构上强制而非约定。
- 与 Inkwell 的关系:共享 sidecar 契约的两个独立应用,不做进程间耦合。

---

## 六、Backlog(不阻塞主线)

| 项目 | 来源 | 备注 |
|------|------|------|
| 股票图时间轴日期标签 bug | PR 4' | 五个未试方向见 D.16.6;niche 功能,顺手再验证 |
| 股票图 D4 主题切换 + 打磨 | PR 4' | 同上 |
| PR 5:InlineRegistry v2(KaTeX inline `$...$`) | Phase 3 | 需 parser-aware 匹配;若 3.5 期间 parser 有改动,重估成本 |
| PR 6:股票图网络/缓存/刷新 capabilities | Phase 3 | 依赖产品层面确认需求 |
| editor.html 文件拆分 | Phase 3 决策 | 触发条件不变:8000+ 行影响开发效率时再议 |
| **方案 B:单 WebView 复用** | Phase 3.5 A/B 决策 | **独立设计议题,时点 Phase 4 前后**。现状是方案 A(每 tab 常驻 WebView,见 `PHASE_3_5_EDITMODE.md` 附录「事故记录:WKWebView 泄漏 + 每-tab 常驻编辑器」):内存随 tab 线性,是过渡形态。B = 全 app 一个编辑器 WebView,切换 = `loadMarkdown` 换内容,内存恒定,且从结构上消除"新旧实例闭包穿越"这类隐患(WKWebView 泄漏事故的菊花链就是这种结构长出来的)。**核心是设计 tab 切换时的状态 flush/恢复协议**:未保存内容 flush、滚动位置与光标记忆(A 已落地的 JS selection 快照/恢复可复用)、Phase 3.5 编辑状态机在某 block 处于源码编辑态时切走的语义(强制提交?保留?)。与 **Phase 4 sidecar 保存时机**有天然交集——flush 协议和 sidecar 写入时机一起设计更省力,故排在 Phase 4 前后并行 |
| Tab LRU 上限 | Phase 3.5 Option A | **过渡性缓解,按需触发**。方案 A 下 N tab = N 个 Web Content 进程;若用户实际打开十几个 tab 导致内存压力,加一个 LRU:超过阈值的非活跃 tab 释放其 WebView(下次切回冷启动重建)。B 落地后此项自动作废,故仅在 B 之前、且确有内存投诉时才做 |

---

## 七、贯穿性原则(从 Phase 3 继承)

1. **源码权威性**:任何功能故障不得破坏 `.md` round-trip
2. **磁盘纯净**:`.md` 永远是标准 Markdown,base64/元数据只存在于 DOM 或 sidecar
3. **不预先抽象**:hook/机制等第二个真实用例出现时再抽(C.4 教训)
4. **范围纪律**:相邻 bug 开独立 issue,不塞进活跃 PR
5. **设计文档先行**:每个 Phase 启动即立文档;实施现实与设计差异如实记录
6. **版本确认**:动手前确认活跃文件版本,防止基于旧文件回归

---

*Document version: 1.0 — 顶层框架定稿,Phase 3.5 启动*
