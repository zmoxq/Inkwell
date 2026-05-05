# Inkwell

A native WYSIWYG Markdown editor for macOS and iOS, inspired by [Typora](https://typora.io). Built with Swift, SwiftUI, and a lightweight WKWebView-based editing engine — no Electron, no web frameworks, no npm.

![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iOS-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen)

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

```
┌──────────────────────────────┐
│         SwiftUI Shell        │
│  ContentView · SidebarView   │
│  EditorToolbarView · AppState│
├──────────────────────────────┤
│    MarkdownEditorView.swift  │
│   WKWebView + JS↔Swift Bridge│
├──────────────────────────────┤
│        editor.html           │
│  Markdown Parser/Serializer  │
│  LiveConverter · SlashMenu   │
│  FoldableHeadings · DragSort │
│  TableOfContents · WordCount │
│  FocusMode · CarouselManager │
└──────────────────────────────┘
```

**Key constraint:** Zero external dependencies. No npm packages, no Swift packages. The JS engine is a single self-contained HTML file. Code syntax highlighting uses highlight.js loaded from CDN.

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
