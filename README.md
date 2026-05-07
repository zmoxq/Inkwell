# Inkwell

A native WYSIWYG Markdown editor for macOS and iOS, inspired by [Typora](https://typora.io). Built with Swift, SwiftUI, and a lightweight WKWebView-based editing engine — no Electron, no web frameworks, no npm.

![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iOS-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen)

## Status

**Phase 3 — Extension Architecture** (in progress, May 2026)

- ✅ Phase 1 — File tree / outline / theme system
- ✅ Phase 2 — Toolbar / shortcuts / live rendering / highlights / tables
- 🚧 Phase 3 — Extension architecture (PR 1 + 2 complete)
	- ✅ ExtensionRegistry: BlockRenderer / BlockDecorator / InlineRenderer (three types)
	- ✅ WebAssets: Bundle asset layer (`inkwell-asset://` URL scheme)
	- ✅ Built-in extensions: highlight-code / highlight-mark / mermaid
	- ⬜ PR 3 — KaTeX display math
	- ⬜ PR 4 — Timeline (custom SVG)

See `docs/PHASE_3_ARCHITECTURE.md` for details.

## Why Inkwell?

Most Markdown editors are either Electron-based (heavy, non-native) or rely on split-pane preview (context-switching). Inkwell renders Markdown inline as you type — like Typora — but as a truly native app. The entire editing engine lives inside a single `editor.html` with zero npm dependencies. Swift handles file I/O, theming, and OS integration; JavaScript handles Markdown parsing, serialization, and the contentEditable surface.

## Features

### Editor
- **True WYSIWYG** — write Markdown, see it rendered inline. No split pane.
- **Clean Markdown round-trip** — files are always saved as standard `.md`.
- **Live syntax conversion** — type `**bold**` and it becomes **bold** instantly. Supports headings, lists, blockquotes, code fences, horizontal rules, and more.
- **Slash command menu** — type `/` to insert headings, lists, code blocks, tables, images, and more from a searchable palette.
- **Format toolbar** — bold, italic, strikethrough, code, highlight, text/background color, lists, quotes, links, tables, and indent controls.
- **Keyboard shortcuts** — ⌘B, ⌘I, ⌘K, ⌘E, ⌘⇧1–6, and many more.
- **Find & Replace** — with case-sensitive option.
- **Code syntax highlighting** — powered by highlight.js via CDN, with automatic light/dark theme switching.
- **Tables** — insert and edit Markdown tables.
- **Images & Carousels** — inline image rendering with multi-image carousel support.

### Navigation & Organization
- **Typora-style sidebar** — recursive file tree with collapsible folders. Attachment folders auto-hidden.
- **Document outline** — auto-numbered heading list with click-to-scroll.
- **Foldable headings** — collapse/expand heading sections. Nested headings fold together.
- **Floating Outline panel** — toolbar button opens a floating panel with auto-numbered headings and scroll-position tracking.
- **Drag & drop reordering** — grab any block's handle to rearrange content.

### Writing Modes
- **Focus Mode** — dims all content except the block you're editing.
- **Typewriter Mode** — keeps the current line centered on screen.
- **Word count & reading time** — live stats in the bottom status bar, with CJK-aware counting.

### Theming
- **7 built-in themes** — Inkwell, GitHub, Nord, Dracula, Solarized Light, Newsprint, ZMZT.
- **Visual theme picker** — card grid with simulated previews.
- **Custom CSS import** — load any `.css` file as a theme.
- **Persistent** — theme preference saved to UserDefaults.

## Architecture

### Architecture Overview

Inkwell is built on SwiftUI + WKWebView. SwiftUI handles file I/O, theming, and OS integration; the WKWebView embeds `editor.html` and handles all Markdown parsing, rendering, and serialization. The two sides communicate bidirectionally via `WKScriptMessageHandler`.

**Phase 3 Extension Architecture** (current) lets all non-core rendering logic plug into editor.html through `ExtensionRegistry` without coupling to the editor core. Three extension types:

| Type           | Responsibility                    | Current instance              |
| -------------- | --------------------------------- | ----------------------------- |
| BlockRenderer  | Takes over fenced block rendering | mermaid                       |
| BlockDecorator | Decorates already-rendered DOM    | highlight-code (highlight.js) |
| InlineRenderer | Inline text fragment replacement  | highlight-mark (`==text==`)   |

**WebAssets asset layer** (introduced in PR 2): extension-dependent JS libraries are loaded from the app Bundle via the custom `inkwell-asset://` URL scheme. Drop asset files into `Inkwell/Resources/WebAssets/` and they're available. See `docs/WEBASSETS.md`.

**Progress**: PR 1 (architecture + migration of existing features) and PR 2 (mermaid + WebAssets) are complete. Next up is PR 3 (KaTeX). Full design in `docs/PHASE_3_ARCHITECTURE.md`.

## Requirements

- macOS 14.0+ / iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Clone the repository
2. Open `Inkwell.xcodeproj` in Xcode
3. For development: disable App Sandbox or enable **Outgoing Connections** in the entitlements file (required for WKWebView and highlight.js CDN)
4. Build and run

## Key Files

| File | Role |
|------|------|
| `editor.html` | JS editing engine — Markdown parser, serializer, live converter, all UI modules |
| `MarkdownEditorView.swift` | WKWebView wrapper + bidirectional Swift↔JS bridge (EditorCoordinator) |
| `EditorToolbarView.swift` | Format toolbar, find/replace bar, color pickers |
| `ContentView.swift` | Main layout — NavigationSplitView with sidebar + editor |
| `SidebarView.swift` | File tree + outline toggle |
| `AppState.swift` | App-wide state — open documents, working directory, theme |
| `DataModels.swift` | FileItem, DocumentState, OutlineItem models |
| `DefaultTheme.swift` | Built-in CSS themes |

## License

MIT
