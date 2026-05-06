import SwiftUI
#if os(macOS)
import AppKit
import Combine
#endif

// MARK: - Format State

/// Tracks the current formatting state at the cursor position.
/// Updated via selectionChange messages from the JS editor.
class EditorFormatState: ObservableObject {
    @Published var isBold = false
    @Published var isItalic = false
    @Published var isStrikethrough = false
    @Published var isInlineCode = false
    @Published var isLink = false
    @Published var blockType = "paragraph"
    @Published var headingLevel = 0
    // Color state
    @Published var textColor: Color = .primary
    @Published var bgColor: Color = .clear
    @Published var hasTextColor: Bool = false
    @Published var hasBgColor: Bool = false

    func update(from dict: [String: Any]) {
        isBold = dict["bold"] as? Bool ?? false
        isItalic = dict["italic"] as? Bool ?? false
        isStrikethrough = dict["strikethrough"] as? Bool ?? false
        isInlineCode = dict["inlineCode"] as? Bool ?? false
        isLink = dict["isLink"] as? Bool ?? false
        blockType = dict["blockType"] as? String ?? "paragraph"
        headingLevel = dict["headingLevel"] as? Int ?? 0

        // Text color
        if let colorStr = dict["textColor"] as? String, !colorStr.isEmpty,
           let c = Color(cssString: colorStr) {
            textColor = c
            hasTextColor = true
        } else {
            hasTextColor = false
        }
        // Background color
        if let bgStr = dict["bgColor"] as? String, !bgStr.isEmpty,
           let c = Color(cssString: bgStr) {
            bgColor = c
            hasBgColor = true
        } else {
            hasBgColor = false
        }
    }
}

// MARK: - Find/Replace State

class FindReplaceState: ObservableObject {
    @Published var isVisible = false
    @Published var showReplace = false
    @Published var searchText = ""
    @Published var replaceText = ""
    @Published var caseSensitive = false
    @Published var matchCount = 0
    @Published var currentMatch = -1
}

// MARK: - Editor Toolbar

struct EditorToolbarView: View {
    @ObservedObject var formatState: EditorFormatState
    var zoomLevel: Int
    var onFormat: (String) -> Void
    var onFindReplace: () -> Void
    var onToggleTOC: () -> Void
    var onZoomTo: (Int) -> Void
    var onExportHTML: () -> Void
    var onExportPDF: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    // Block type picker
                    blockTypePicker

                    toolbarDivider

                    // Inline formatting
                    FormatBtn(icon: "bold", tip: "Bold (⌘B)", active: formatState.isBold) {
                        onFormat("bold")
                    }
                    FormatBtn(icon: "italic", tip: "Italic (⌘I)", active: formatState.isItalic) {
                        onFormat("italic")
                    }
                    FormatBtn(icon: "strikethrough", tip: "Strikethrough (⌘⇧D)", active: formatState.isStrikethrough) {
                        onFormat("strikethrough")
                    }
                    FormatBtn(icon: "chevron.left.forwardslash.chevron.right", tip: "Code (⌘E)", active: formatState.isInlineCode) {
                        onFormat("inlineCode")
                    }

                    toolbarDivider

                    // Color pickers
                    ColorPickerBtn(
                        icon: "textformat",
                        indicatorColor: formatState.hasTextColor ? formatState.textColor : Color.primary.opacity(0.25),
                        tooltip: "字体颜色",
                        onColorPicked: { color in
                            if let hex = color.hexString {
                                onFormat("textColor:\(hex)")
                            }
                        },
                        onClear: { onFormat("textColor:") }
                    )

                    ColorPickerBtn(
                        icon: "highlighter",
                        indicatorColor: formatState.hasBgColor ? formatState.bgColor : Color.primary.opacity(0.25),
                        tooltip: "背景色",
                        onColorPicked: { color in
                            if let hex = color.hexString {
                                onFormat("bgColor:\(hex)")
                            }
                        },
                        onClear: { onFormat("bgColor:") }
                    )

                    toolbarDivider

                    // Lists
                    FormatBtn(icon: "list.bullet", tip: "Bullet List (⌘⇧8)", active: formatState.blockType == "bulletList") {
                        onFormat("bulletList")
                    }
                    FormatBtn(icon: "list.number", tip: "Numbered List (⌘⇧9)", active: formatState.blockType == "orderedList") {
                        onFormat("orderedList")
                    }
                    FormatBtn(icon: "checklist", tip: "Task List (⌘⇧X)", active: formatState.blockType == "taskList") {
                        onFormat("taskList")
                    }

                    toolbarDivider

                    // Block elements
                    FormatBtn(icon: "text.quote", tip: "Quote (⌘⇧')", active: formatState.blockType == "blockquote") {
                        onFormat("blockquote")
                    }
                    FormatBtn(icon: "curlybraces", tip: "Code Block (⌘⇧E)", active: formatState.blockType == "codeBlock") {
                        onFormat("codeBlock")
                    }
                    FormatBtn(icon: "minus", tip: "Horizontal Rule", active: false) {
                        onFormat("horizontalRule")
                    }

                    toolbarDivider

                    // Insert
                    FormatBtn(icon: "link", tip: "Link (⌘K)", active: formatState.isLink) {
                        onFormat("link")
                    }
                    FormatBtn(icon: "tablecells", tip: "Insert Table", active: false) {
                        onFormat("table")
                    }
                    FormatBtn(icon: "rectangle.on.rectangle", tip: "Insert Image Carousel", active: false) {
                        onFormat("carousel")
                    }

                    toolbarDivider

                    // Indent
                    FormatBtn(icon: "increase.indent", tip: "Indent", active: false) {
                        onFormat("increaseIndent")
                    }
                    FormatBtn(icon: "decrease.indent", tip: "Outdent", active: false) {
                        onFormat("decreaseIndent")
                    }

                    Spacer()

                    // Find & Replace
                    FormatBtn(icon: "magnifyingglass", tip: "Find (⌘F)", active: false) {
                        onFindReplace()
                    }
                }
                .padding(.horizontal, 12)
            }

            toolbarDivider

            // Zoom — single menu
            Menu {
                ForEach([50, 75, 90, 100, 110, 125, 150, 175, 200], id: \.self) { pct in
                    Button {
                        onZoomTo(pct)
                    } label: {
                        HStack {
                            Text("\(pct)%")
                            if pct == zoomLevel {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Zoom (\(zoomLevel)%)")

            toolbarDivider

            // Export
            Menu {
                Button(action: onExportHTML) {
                    Label("Export HTML…", systemImage: "doc.text")
                }
                Button(action: onExportPDF) {
                    Label("Export PDF…", systemImage: "doc.richtext")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Export")

            toolbarDivider

            // Outline
            FormatBtn(icon: "list.bullet.indent", tip: "Outline", active: false) {
                onToggleTOC()
            }
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Block Type Picker

    private var blockTypePicker: some View {
        Menu {
            Button("Paragraph") { onFormat("paragraph") }
            Divider()
            Button("Heading 1") { onFormat("heading1") }
            Button("Heading 2") { onFormat("heading2") }
            Button("Heading 3") { onFormat("heading3") }
            Button("Heading 4") { onFormat("heading4") }
        } label: {
            HStack(spacing: 4) {
                Text(blockTypeLabel)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 70, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    private var blockTypeLabel: String {
        switch formatState.blockType {
        case "h1": return "Heading 1"
        case "h2": return "Heading 2"
        case "h3": return "Heading 3"
        case "h4": return "Heading 4"
        case "h5": return "Heading 5"
        case "h6": return "Heading 6"
        case "blockquote": return "Quote"
        case "codeBlock": return "Code"
        case "bulletList": return "Bullet List"
        case "orderedList": return "Num List"
        case "taskList": return "Task List"
        default: return "Paragraph"
        }
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 16).padding(.horizontal, 4)
    }
}

// MARK: - Color Picker Button

/// 带颜色指示条的颜色选择器按钮。
/// 点击弹出系统取色器；右键菜单可清除颜色。
struct ColorPickerBtn: View {
    let icon: String
    let indicatorColor: Color
    let tooltip: String
    var onColorPicked: (Color) -> Void
    var onClear: () -> Void

    @State private var pickerColor: Color = .red
    @State private var showPicker = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // 图标按钮
            Button {
                showPicker = true
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help(tooltip)
            .contextMenu {
                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("清除\(tooltip)", systemImage: "xmark.circle")
                }
            }

            // 颜色指示条（底部细线）
            RoundedRectangle(cornerRadius: 1)
                .fill(indicatorColor)
                .frame(width: 18, height: 2.5)
                .offset(y: 2)
        }
        .frame(width: 28, height: 28)
        // 透明的 ColorPicker overlay，只在 showPicker 时激活
        .background(
            Group {
                if showPicker {
                    ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                        .labelsHidden()
                        .opacity(0.011)
                        .onChange(of: pickerColor) { _, newColor in
                            onColorPicked(newColor)
                            showPicker = false
                        }
                }
            }
        )
    }
}

// MARK: - Format Button

struct FormatBtn: View {
    let icon: String
    let tip: String
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: active ? .bold : .regular))
                .foregroundStyle(active ? Color.accentColor : .primary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.accentColor.opacity(0.12) :
                              hovering ? Color.primary.opacity(0.06) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tip)
    }
}

// MARK: - Find & Replace Bar

struct FindReplaceBar: View {
    @ObservedObject var state: FindReplaceState
    var onFind: (String, Bool) -> Void
    var onFindNext: () -> Void
    var onFindPrevious: () -> Void
    var onReplace: (String) -> Void
    var onReplaceAll: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Find row
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Find…", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { onFindNext() }
                    .onChange(of: state.searchText) { _, val in
                        onFind(val, state.caseSensitive)
                    }

                if !state.searchText.isEmpty {
                    Text(state.matchCount > 0
                         ? "\(state.currentMatch + 1)/\(state.matchCount)"
                         : "No results")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                Button(action: {
                    state.caseSensitive.toggle()
                    onFind(state.searchText, state.caseSensitive)
                }) {
                    Text("Aa")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(state.caseSensitive ? Color.accentColor.opacity(0.15) : .clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Case Sensitive")

                Button(action: onFindPrevious) {
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(state.matchCount == 0)

                Button(action: onFindNext) {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(state.matchCount == 0)

                Button(action: { state.showReplace.toggle() }) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 11))
                        .foregroundStyle(state.showReplace ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Replace")

                Button(action: {
                    onClose()
                    state.isVisible = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Replace row
            if state.showReplace {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))

                    TextField("Replace…", text: $state.replaceText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit { onReplace(state.replaceText) }

                    Button("Replace") { onReplace(state.replaceText) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                        .disabled(state.matchCount == 0)

                    Button("All") { onReplaceAll(state.replaceText) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                        .disabled(state.matchCount == 0)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }
}

// MARK: - Color Extensions

extension Color {
    /// 返回 "#RRGGBB" 格式的十六进制字符串
    var hexString: String? {
        #if os(macOS)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(c.redComponent   * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent  * 255)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(r * 255), gi = Int(g * 255), bi = Int(b * 255)
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 从 CSS 颜色字符串初始化（支持 #RRGGBB 和 rgb(r,g,b)）
    init?(cssString: String) {
        let s = cssString.trimmingCharacters(in: .whitespaces)

        // rgb(r, g, b) / rgba(r, g, b, a)
        if s.hasPrefix("rgb") {
            let nums = s
                .replacingOccurrences(of: "rgba(", with: "")
                .replacingOccurrences(of: "rgb(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard nums.count >= 3 else { return nil }
            self = Color(red: nums[0] / 255, green: nums[1] / 255, blue: nums[2] / 255)
            return
        }

        // #RRGGBB / #RGB
        var hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self = Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}
