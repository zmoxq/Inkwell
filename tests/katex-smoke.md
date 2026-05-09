# KaTeX Display Math 烟雾测试 (Phase 3 PR 3)

> 本文档用于验证 PR 3 KaTeX display math 接入是否成功。
> 在 macOS 和 iOS 都跑一遍。
> 详见 PHASE_3_ARCHITECTURE.md 附录 D。

## 1. 基本公式

$$
E = mc^2
$$

预期:质能方程居中渲染,使用 KaTeX 字体。

## 2. 分式

$$
\frac{a}{b} + \frac{c}{d} = \frac{ad + bc}{bd}
$$

预期:分式正确显示,横线居中。

## 3. 求和与积分

$$
\sum_{i=1}^{n} i^2 = \frac{n(n+1)(2n+1)}{6}
$$

$$
\int_{-\infty}^{\infty} e^{-x^2} \, dx = \sqrt{\pi}
$$

预期:求和/积分符号上下限正确,Σ/∫ 符号大尺寸。

## 4. 矩阵

$$
\begin{pmatrix}
a & b \\
c & d
\end{pmatrix}
\begin{pmatrix}
x \\
y
\end{pmatrix}
=
\begin{pmatrix}
ax + by \\
cx + dy
\end{pmatrix}
$$

预期:矩阵带括号,元素对齐。

## 5. 上下标 + 希腊字母

$$
\alpha_n = \frac{1}{\sqrt{2\pi}} \int_{-\infty}^{\infty} f(\xi) e^{-i\omega\xi} \, d\xi
$$

预期:α/π/ξ/ω/∞ 等希腊字母与符号正确(依赖 KaTeX 字体加载成功)。

## 6. 对齐环境

$$
\begin{aligned}
(a+b)^2 &= a^2 + 2ab + b^2 \\
(a-b)^2 &= a^2 - 2ab + b^2 \\
(a+b)(a-b) &= a^2 - b^2
\end{aligned}
$$

预期:三行公式按 `&=` 对齐。

---

## 故障注入测试(开工时手工跑一遍)

### A. 语法错(应该显示 KaTeX 自带红色错误框,不丢源码)

$$
\frac{1}{ \unknownmacro
$$

预期:KaTeX 渲染出红色错误提示("Undefined control sequence" 或类似),源码完整保留;**不会**进入 ctx.setError 路径(因为 throwOnError: false)。

### B. 库未加载(临时把 katex.min.js 重命名,reload 应该看到 ctx.setError)

(操作:在 `WebAssets/` 里把 `katex.min.js` 临时改名为 `katex.min.js.bak`,重新启动 app,加载本文件。)

预期:此章节所有公式块都显示黄色 syntax 错误框(`KaTeX library not loaded. Check inkwell-asset:///katex.min.js is reachable...`),源码完整保留。Console 里能看到 `[Extension:katex-display]` 上报。

测试完恢复文件名。

---

## Round-trip 测试

1. 打开本文件,确认所有公式正确渲染
2. 编辑此文件(在某个公式下面加一句普通文本),保存
3. 在 Finder 里查看 .md 文件原始内容,确认:
   - 所有 `$$...$$` 完整保留含定界符
   - 没有任何 base64 残留
   - 普通段落、标题、列表正常 round-trip

---

## 主题切换测试

1. 系统偏好设置切换 dark mode ↔ light mode
2. 预期:KaTeX 公式颜色自动跟随主题色变化(`currentColor` 继承)
3. 预期:**公式 DOM 不重新渲染**(Console 里观察不到 `[Extension:katex-display] render` 日志重复触发)
4. 切到自定义主题(GitHub / Nord / Dracula / Solarized / Newsprint / ZMZT)各看一次
5. 预期:每个主题下公式颜色都正常,无 hardcode 黑/白色不响应主题

---

## 现有功能无退化测试

跑现有的 `tests/mermaid-smoke.md`、`==highlight==` 测试用例、code block 高亮测试,确认:
- 所有 mermaid 图表渲染正常
- `==highlight==` 行为不变
- code block hljs 着色正常
- 主题切换 mermaid 自动重渲染(rerenderOn 路径)
- KaTeX 公式与 mermaid 在同一文档共存时互不影响
