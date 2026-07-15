# Inline Sanitization Test Cases

> Each section targets one injection vector.
> Expected: all payloads render as escaped text, no JS execution, no attribute breakout.

## 1. Image alt attribute injection

![" onload="alert('xss')](test.png)

Expected: image tag with literal `" onload="alert('xss')` in alt text, no event handler.

## 2. Image src attribute injection

![test](x" onerror="alert('xss'))

Expected: broken image with literal src, no script execution.

## 3. Link text HTML injection

[<img src=x onerror=alert('xss')>](http://example.com)

Expected: link with escaped `<img>` as visible text, not an actual image element.

## 4. Link href javascript: protocol

[click me](javascript:alert(document.cookie))

Expected: "click me" rendered as plain text, no link.

## 5. Link href JAVASCRIPT: (case variant)

[click me](JAVASCRIPT:alert(1))

Expected: plain text, no link.

## 6. Link href with control characters

[click me](java	script:alert(1))

Expected: plain text, no link (tab character inside scheme).

## 7. Link href vbscript:

[click me](vbscript:MsgBox("xss"))

Expected: plain text, no link.

## 8. Link href data:

[click me](data:text/html,<script>alert(1)</script>)

Expected: plain text, no link.

## 9. Link href safe protocols (should work)

[http link](http://example.com)

[https link](https://example.com)

[mailto link](mailto:test@example.com)

[relative link](./page.md)

[anchor link](#section)

Expected: all five render as clickable links.

## 10. Raw HTML in paragraph

<script>alert('xss')</script>

Expected: literal text `<script>alert('xss')</script>`, no execution.

## 11. Raw HTML in heading

## <img src=x onerror=alert('xss')>

Expected: heading with literal text `<img src=x onerror=alert('xss')>`.

## 12. HTML inside bold/italic

**<script>alert('xss')</script>**

*<img src=x onerror=alert('xss')>*

Expected: bold/italic text with escaped HTML entities.

## 13. Inline code (PR 3 — should still work)

`<script>alert('xss')</script>`

Expected: code element showing literal `<script>alert('xss')</script>`.

## 14. Highlight extension

==<script>alert('xss')</script>==

Expected: highlighted text with escaped HTML entities.

## 15. Normal content (no regression)

This is **bold**, *italic*, ~~strikethrough~~, and `inline code`.

![valid image](https://example.com/photo.jpg)

[valid link](https://example.com)

==highlighted text==

Expected: all formatting renders correctly.
