# Phase 4: Sidecar 元数据 Schema 设计

> 状态:设计定稿(2026-07-14)。本文档是 Inkwell 与未来 AI 组织工具(Phase 6)之间的公开契约。
> 契约的长寿性来自信封规则(层所有权、单一写者、未知字段保留),不来自字段清单。

## 1. 定位与设计原则

Sidecar 是笔记的元数据容器:所有不属于正文、但需要长期跟随笔记的信息都存于此,换取 `.md` 永远干净——无 frontmatter、无 UUID 注释,任何编辑器打开都是纯正文。

Inkwell 与 Phase 6 AI 工具不直接通信,靠读写同一个 sidecar 协作。设计原则:

1. **`.md` 不携带任何元数据**。正文是标准 Markdown,这是不可谈判的前提。
2. **每层单一写者**。Inkwell 写 `system` + `user`;AI 工具只写 `ai`。所有权永不交叉,因此两个应用永远不需要合并逻辑。
3. **未知字段必须原样回写**。任何写入方:读整个文件 → 只改自己的层 → 完整写回(含一切不认识的字段)。这是前向兼容的基石,比版本号更重要。
4. **信封优先于字段**。V1 精确规定结构与规则,字段清单保持最小;新增字段零成本(见规则 3),所以起步越小越好。

## 2. 文件绑定

**命名**:笔记 `P.md` 的 sidecar 为同目录下的 `P.md.json`(如 `投资笔记.md` → `投资笔记.md.json`)。判定规则:一个 `.json` 文件是 sidecar,当且仅当去掉 `.json` 后缀所得路径以 `.md` 结尾且该文件存在。

**理由**:与 `.md` 并排、用户在 Finder 可见、拷贝笔记时自然带上——摄影行业 XMP sidecar(`photo.raw` + `photo.xmp`)二十年的成熟模式。集中存储(库根 `.inkwell/`)被否决:path↔UUID 映射表本身就是一份会腐烂的元数据;隐藏文件被否决:违背 local-first 的可见性,且部分同步/备份工具跳过点文件。

**惰性创建**:仅在首次有元数据需要写入时创建 sidecar。无标签、无 AI 成果的笔记不产生文件,避免文件数翻倍。创建时必须立即完整写入 `system` 层(含 `contentHash`)——否则该 sidecar 在首次正文保存前不具备孤儿恢复能力。

**应用内改名/移动**:Inkwell 负责同步移动两个文件。

**孤儿恢复**:应用外改名导致 sidecar 失配时,扫描库:对每个无主 sidecar,用其 `system.contentHash` 与所有无 sidecar 的 `.md` 做哈希匹配,唯一命中即重新配对;多个命中(内容完全相同的笔记)或零命中则不自动配对,孤儿静置。**唯一性必须双向成立**:一个孤儿命中多个候选 → 该孤儿静置;一个候选被多个孤儿命中 → 涉事孤儿全部静置——两个孤儿哈希相同,但 user/ai 层内容可能不同,任选其一等于把随机一份元数据绑到正文上,即错配。任一方向多重,零重绑。纯哈希、不做模糊匹配——改名不改内容是绝对主流场景,哈希精确命中;启发式猜错的代价(把 A 的元数据贴到 B 上)比丢失元数据更糟。模糊匹配留作日后增强,schema 无需为它预留任何东西。

## 3. Schema 结构

```json
{
  "schemaVersion": 1,
  "system": {
    "contentHash": "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
    "createdAt": "2026-07-14T08:30:00Z",
    "modifiedAt": "2026-07-14T09:12:45Z"
  },
  "user": {
    "tags": ["投资", "读书笔记"]
  },
  "ai": {}
}
```

### 顶层

| 字段 | 类型 | 说明 |
|---|---|---|
| `schemaVersion` | integer | 当前为 `1`。仅破坏性结构变更时 +1;新增字段不升版(靠未知字段保留规则兼容)。读到高于自身支持的版本:转只读,不写入,提示升级。 |
| `system` | object | Inkwell 专属写入。 |
| `user` | object | 人的判断,经 Inkwell UI 写入。 |
| `ai` | object | AI 工具专属写入。 |

### system 层(写者:Inkwell)

| 字段 | 类型 | 说明 |
|---|---|---|
| `contentHash` | string | `"sha256:" + 小写十六进制`,对 `.md` 磁盘字节(UTF-8)整体计算。前缀留出算法演进空间。每次保存正文后更新。兼任两职:孤儿恢复的配对键;Phase 6 判断「笔记在 AI 上次处理后是否变过」的过期判据。 |
| `createdAt` | string | ISO 8601 UTC,笔记创建时间(sidecar 首次创建时以文件系统信息初始化)。 |
| `modifiedAt` | string | ISO 8601 UTC,Inkwell 最近一次保存正文的时间。 |

设备本地态(光标位置、滚动位置等)**不入 sidecar**——跨应用契约里不该有单设备的临时状态。

### user 层(写者:Inkwell,代表人的判断)

| 字段 | 类型 | 说明 |
|---|---|---|
| `tags` | string[] | 标签。经 UI 赋予;正文不引入 `#tag` 内联语法(见 §5 决策记录)。 |

### ai 层(写者:Phase 6 AI 工具)

V1 **不定义任何字段**,只保证:层存在、单一写者、未知字段保留。字段由 Phase 6 工具在真实需求下自行定义——现在猜字段大概率猜错,而信封规则已足以保护它未来写入的一切。AI 工具可随时整层重算覆盖 `ai`,不会波及人的决定。

**采纳语义**:用户采纳某条 AI 建议(如建议标签)时,Inkwell 将内容**拷贝进 user 层**(如写入 `user.tags`),`ai` 层原封不动。采纳的瞬间,信息从「AI 的建议」变为「人的判断」,归层名副其实;单一写者不被破坏。

## 4. 写入协议(契约条款,所有写入方必须遵守)

1. 读取整个文件并解析。
2. 只修改属于自己的层;其余一切字段(含不认识的)原样保留。
3. 写回前检查文件 mtime 是否与读取时一致;不一致则重读、重新应用修改。
4. 写入采用临时文件 + rename 原子替换,防止写一半崩溃留下损坏文件。

V1 实现范围:Inkwell 是唯一写入方,并发实际不存在,故只实现第 1、2、4 条;第 3 条作为契约条款写死在此,Phase 6 工具实现时照办即可(现在实现它是单写入方环境下测不到的死代码)。

## 5. 决策记录(含被否决方案)

| # | 决策 | 选择 | 被否决方案及理由 |
|---|---|---|---|
| 1 | 绑定方式 | 同目录同名 `P.md.json` | 集中存储:映射表是第二个会腐烂的真相;隐藏文件:不可见、同步工具风险 |
| 2 | 孤儿恢复 | 纯内容哈希,唯一命中才配对(唯一性双向成立:孤儿→候选、候选→孤儿) | 模糊匹配:猜错代价高于丢失,V1 过度设计;不恢复:与 Phase 6 相悖,AI 层积累不可丢;先到先得(候选被多个同哈希孤儿争夺时取一):user/ai 层可能不同,随机绑定即错配——2026-07-16 实现审查暴露的对称盲区,原文只规定了孤儿→候选方向 |
| 3 | 版本策略 | 顶层单一整数 + 未知字段保留 | semver:读写方只有两个自控应用,表达力无受众;每层独立版本:版本矩阵复杂化 |
| 4 | 采纳语义 | 拷贝进 user 层 | ai 层就地标记 accepted:破坏单一写者,引入跨应用合并 |
| 5 | ai 层范围 | 空信封,字段由 Phase 6 定义 | 预设字段:替不存在的产品做需求,猜错要背迁移成本 |
| 6 | `#tag` 内联语法(Phase 3 遗留决策) | **不引入**。标签只存 `user.tags` | 正文为真相:第二份真相需同步,解析歧义多(代码块、标题),与「.md 不携带元数据」相悖;双向同步:复杂度最高,冲突场景最多。日后可加「输入 #xx 自动收入 user.tags」的便捷入口,属输入交互,不改 schema |
| 7 | V1 字段集 | 极简(见 §3) | 预加 pinned/aliases:功能尚不存在,死字段;真需要时新增零成本 |
| 8 | 并发控制 | 协议入契约,V1 只实现原子写 | V1 实现 mtime 重试:单写入方环境下的死代码 |

## 6. V1 实施范围(Inkwell 侧)

- sidecar 惰性创建、读写(遵守 §4 第 1、2、4 条)
- 保存正文时更新 `contentHash` / `modifiedAt`
- 标签 UI → `user.tags`
- 应用内改名/移动同步搬移 sidecar
- 库扫描时的孤儿检测与哈希配对
- `schemaVersion` 高于支持版本时转只读

不在 V1:ai 层的任何展示 UI(Phase 6 时再做)、模糊配对、mtime 冲突重试。

## 附录:实施记录

### PR 1 — SidecarStore 数据层(2026-07-16)

实现:`Models/SidecarDocument.swift`(字典背书模型,刻意不用 Codable——Codable 解码丢未知键,违反 §1 规则 3)+ `Models/SidecarStore.swift`(无状态服务,语义操作 API:`setTags` / `recordContentSave`,层所有权由 API 形状强制)。

**契约解读(§2 vs §6 的空隙)**:`recordContentSave` 在 sidecar 不存在时不惰性创建,直接 no-op。理由:§2 惰性创建的目的即是让无元数据的笔记不产生文件;若正文保存也触发创建,则每个保存过的笔记都会有 sidecar,惰性创建形同虚设。首个真正的元数据写入(如 setTags)才创建文件,创建时以当时的 .md 磁盘字节完整写入 system 层。

其余按契约原文实现:三态读取(absent / writable / readOnly)、损坏 JSON 拒写不覆盖(schemaVersion 缺失或非整数同样按损坏处理)、temp 文件 + rename(2) 原子替换、输出 prettyPrinted + sortedKeys(用户在 Finder 可见,且 git diff 稳定)。

### PR 2 — 生命周期挂接(2026-07-16)

实现:`Models/NoteFileOperations.swift`(笔记级成对操作:saveNote / renameNote / trashNote)。AppState 的 4 处正文写盘点(saveCurrentDocument、closeTab、closeOtherTabs、closeAllTabs)收敛到 `saveNote`,sidecar 更新失败只记 log、不阻断正文保存。

**实施现实**:应用内当时并无 rename/move/delete 的任何 UI 或操作入口(AppState 只有 open/create/save)。经确认,本 PR 只交付操作层 + 单测;UI 挂接(sidebar context menu、开标签页时的 URL 同步——牵涉 `MarkdownDocument.url` 由 let 改 var)留给后续 PR。在 UI 挂接完成之前,§2「应用内改名同步搬移」对用户实际不生效(应用外改名依赖孤儿恢复,亦未实现)。

**冲突决策**:renameNote 目标 .md 已存在 → 拒绝整个操作;目标位置存在孤儿 sidecar → 先移入系统废纸篓(可恢复,不硬删)再搬入我方文件——§2 认定错配比丢失更糟,孤儿留在原名下必然误配到搬入的笔记。删除走 `FileManager.trashItem`,sidecar 先行,保证部分失败时元数据不被静默孤立。

### PR 2.5 — 文件管理 UI(2026-07-16)

实现:sidebar 文件行 context menu(Rename… / Move to Trash,均经 `AppState.renameNote` / `deleteNote` → NoteFileOperations,不直接动文件);`MarkdownDocument.url` 由 let 改 `@Published var`,开着的 tab 在改名后 URL、标题自动跟随;删除开着的笔记时 tab 关闭且**丢弃未保存修改**(保存会让刚删的路径复活)。rename 仅同目录改名,不含跨目录移动。

**未保存修改的顺序**:先保存到旧路径,再搬移。保存后磁盘状态完整自洽,搬移是对最新字节的纯成对操作,`saveNote` 写入的 contentHash 与被搬字节一致,任何中断点哈希配对链路不脱节;搬移失败时全部内容已安全落在旧路径。

**附件耦合的实测结论与决策**:普通图片经 WebView base URL(笔记所在目录)相对解析,与笔记文件名零耦合,同目录改名不断;`readLocalFile` 桥(现用户仅 stockchart 本地 CSV)因 D.15 的 `<docname>/` 前缀契约,改名后重开笔记即断(live session 内 coordinator 持旧 URL,暂不受影响)。决策:rename 不设障碍,此限制如实记录;修复归属 resolver 契约层(前缀基准由文件名改为目录),属 Phase 3 安全设计变更,单独立项。改名后附件文件夹保持旧名,功能完好,仅命名耦合失效——新旧附件可能分居两个文件夹。

> **已修复(2026-07-16,独立 resolver PR)**:D.15 修订为目录基准(见 PHASE_3_ARCHITECTURE.md §十一),`readLocalFile` 解析不再依赖笔记文件名,stockchart 本地 CSV 引用在 rename 后照常工作。上段保留作为当时决策的历史记录。

**已知陈旧项(不处理)**:`recentFiles` 中的旧 URL 在改名/删除后不同步(应用外操作同样触发的既有问题)。

### PR 3 — 孤儿扫描与重绑(2026-07-16)

实现:`Models/OrphanSidecarScanner.swift`(无状态,单次全库枚举),挂接于 `workingDirectory` didSet,跑在 utility 后台队列,结果只记 log。

按契约 §2 原文实现:sidecar 判定 = 去 `.json` 后缀以 `.md` 结尾(`.tmp-` 残留天然不命中);无孤儿即返回、零哈希成本;候选(无 sidecar 的 .md)全库范围、每个只哈希一次、可跨子目录配对;唯一命中走 `FileManager.moveItem` 纯 rename,字节零修改(因此不受 schemaVersion 只读限制约束——只读约束的是内容写入);多命中/零命中/孤儿自身 contentHash 不可读 → 静置 + log。

**同轮碰撞:从先到先得修正为双向唯一(2026-07-16 二次修复)**。首版实现对「两个相同孤儿争一个候选」采用先到先得——顺序处理 + `fileExists` 防御,恰好一个获胜。实现审查指出这是契约漏洞:两孤儿 contentHash 相同,但 user/ai 层内容可能不同,先到先得等于随机把一份元数据绑到候选正文上,正是 §2「错配比丢失更糟」要排除的情形;§2 原文只规定了孤儿→候选方向的唯一性,对称方向是盲区。修复:匹配改为三阶段(收集全部命中关系 → 检查双向唯一 → 统一执行重绑,不边扫边绑),候选被多个孤儿命中时涉事孤儿全部静置、记 ambiguous。§2 与 §5 决策表已同步补齐。「目标命名位必空」由候选定义 + 双向唯一保证,`fileExists` 检查降级为纯防御。

### PR 4 — 标签 UI + 只读提示(2026-07-16,Phase 4 收官)

实现:`Views/TagBarView.swift`,钉在 toolbar 与 WKWebView 之间的固定高度(30pt)chip 行,正文从其下方滚动穿过,editor.html 零改动。磁盘为真相:切 tab(编辑区 `.id(doc.id)` 整块重建)与 rename(观察 `document.url`)时重读 sidecar;增删经 `SidecarStore.setTags`(首个标签触发惰性创建),乐观更新、写盘失败回滚 + 行内提示。空态形态:极淡 tag glyph(~25% opacity)常驻,行 hover 显形并出现 Add Tag 文案,行高恒定无跳动。

只读态(schemaVersion > 1):chips 照常显示、编辑禁用,锁图标 + 无术语提示 "Created by a newer version of Inkwell — view only.";损坏态同样禁用,警告图标 + "This note's extra info couldn't be read."。提示语言随现有 UI 用英文。

**V1 清单(§6)至此全部完成**:惰性创建读写(PR 1)、保存钩子(PR 2)、改名/删除同步搬移 + UI(PR 2/2.5)、孤儿扫描重绑(PR 3)、标签 UI 与只读提示(PR 4)。
