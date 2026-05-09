# WebAssets 扩展资产管理

> Phase 3 PR 2 引入。本文档说明如何向 Inkwell 添加、更新或移除 Web 扩展资产
> （JS 库、CSS、字体等）。

---

## 工作原理

`Inkwell/WebAssets/` 是一个 Xcode folder reference，加入 target 的
**Copy Bundle Resources** 阶段。app 启动时 `WebAssets/` 整个文件夹与 app 二进制
一起出现在 `.app` 包内。

`InkwellAssetSchemeHandler` 注册自定义 URL scheme `inkwell-asset://`，
WKWebView 中所有形如 `inkwell-asset:///<path>` 的请求都被路由到这个 handler，
它从 Bundle 内的 `WebAssets/` 文件夹读取对应文件并返回。

editor.html 中通过 `<script src="inkwell-asset:///foo.js">` 即可使用。

**好处**：
- 资产跟随 app 二进制，用户更新 app 自动更新资产版本
- 不污染用户文档目录
- 不需要复制 IO，从 Bundle 直接读
- 所有未来扩展（KaTeX、自绘 timeline 等）共用此 handler

---

## 添加新资产

1. 把资产文件丢进 `Inkwell/WebAssets/`
2. 确认它出现在 Xcode target 的 Copy Bundle Resources（folder reference 自动包括子文件，无需逐个加）
3. 在 editor.html 引用：
   ```html
   <script src="inkwell-asset:///your-file.js"></script>
   <link rel="stylesheet" href="inkwell-asset:///your-file.css">
   ```
4. 更新 `WebAssets/manifest.json`（人读用，记录版本/出处/许可证）

---

## 更新现有资产（以 Mermaid 为例）

```bash
# 1. 拉新版
cd /tmp
rm -rf mermaid-update && mkdir mermaid-update && cd mermaid-update
npm pack mermaid@latest
tar -xzf mermaid-*.tgz

# 2. 替换文件
cp package/dist/mermaid.min.js /path/to/Inkwell/WebAssets/mermaid.min.js

# 3. 更新 manifest.json（手动改 version/updated/size_bytes）

# 4. Xcode build & 测
#    打开 tests/mermaid-smoke.md 跑一遍，确认没有 breaking change

# 5. git commit
```

**关于 breaking change**：Mermaid 历史上有过 API 变更（init/initialize/run 命名迁移）。
更新版本后必须打开 `tests/mermaid-smoke.md`，确认所有图表类型都正常渲染。
如果某种图表崩了，去 [Mermaid changelog](https://github.com/mermaid-js/mermaid/blob/develop/CHANGELOG.md)
查 breaking change，对应修改 editor.html 里的 mermaid renderer 调用代码。

---

## 移除资产

1. 删除 `Inkwell/WebAssets/<file>`
2. 在 editor.html 删除对应 `<script>` / `<link>` 引用
3. 删除使用该资产的 ExtensionRegistry 注册
4. 在 `manifest.json` 删除对应条目

---

## 当前资产清单

详见 `WebAssets/manifest.json`。

| 资产 | 版本 | 用途 |
|------|------|------|
| mermaid.min.js | 11.14.0 | Phase 3 PR 2 — 流程图 / 时序图等 |

---

## 故障排查

**症状**：浏览器 Console 报 `Failed to load resource: ... inkwell-asset:///foo.js`

可能原因：
1. 文件没加入 Bundle Resources（Xcode 项目检查 target → Build Phases → Copy Bundle Resources，确认 WebAssets/ 在列表里）
2. 文件名拼写错误（区分大小写）
3. 路径里多了/少了 `/`——正确格式是 `inkwell-asset:///foo.js`（三个斜杠：scheme、host 留空、根路径）

排查工具：在 Xcode console 看 `InkwellAssetSchemeHandler` 上报的错误，
具体哪个路径解析失败。
