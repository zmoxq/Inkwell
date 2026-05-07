# Mermaid Smoke Test

> 用于每次更新 mermaid.min.js 版本后验证。打开此文件，确认每个图都正常渲染。
> 任意一个图没渲染或显示错误 → 检查 Mermaid changelog 看是否 breaking change。

---

## 1. Flowchart（最基本）

```mermaid
graph TD
  A[Start] --> B{Is it working?}
  B -->|Yes| C[Great!]
  B -->|No| D[Debug]
  D --> B
```

---

## 2. Sequence Diagram

```mermaid
sequenceDiagram
  participant User
  participant App
  participant DB
  User->>App: Click Save
  App->>DB: INSERT
  DB-->>App: OK
  App-->>User: Saved!
```

---

## 3. Gantt Chart

```mermaid
gantt
  title PR 2 Timeline
  dateFormat  YYYY-MM-DD
  section Architecture
  WebAssets       :2026-05-07, 1d
  Mermaid接入      :2026-05-07, 1d
  section Testing
  烟雾测试         :2026-05-08, 1d
```

---

## 4. State Diagram

```mermaid
stateDiagram-v2
  [*] --> Draft
  Draft --> Submitted: submit()
  Submitted --> Approved: approve()
  Submitted --> Rejected: reject()
  Approved --> [*]
  Rejected --> Draft: revise()
```

---

## 5. Class Diagram

```mermaid
classDiagram
  class ExtensionRegistry {
    +registerBlock(spec)
    +registerInline(spec)
    +registerBlockDecorator(spec)
  }
  class BlockRenderer
  class BlockDecorator
  class InlineRenderer
  ExtensionRegistry --> BlockRenderer
  ExtensionRegistry --> BlockDecorator
  ExtensionRegistry --> InlineRenderer
```

---

## 6. Pie Chart

```mermaid
pie title PR 2 时间分布
  "WebAssets 抽象" : 30
  "Mermaid 接入" : 40
  "测试与文档" : 30
```

---

## 7. 故意的语法错（应显示 syntax error，不是 runtime error）

```mermaid
graph TD
  A[Start --> B
  此处缺少右方括号
```

期望：黄色（syntax）错误框，不是红色（runtime）错误框。

---

## 8. 主题切换测试

切换 macOS 系统主题（System Settings → Appearance → Dark/Light），
上面所有图表应该立即重新渲染为对应主题色。
