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
    
    func update(from dict: [String: Any]) {
        isBold = dict["bold"] as? Bool ?? false
        isItalic = dict["italic"] as? Bool ?? false
        isStrikethrough = dict["strikethrough"] as? Bool ?? false
        isInlineCode = dict["inlineCode"] as? Bool ?? false
        isLink = dict["isLink"] as? Bool ?? false
        blockType = dict["blockType"] as? String ?? "paragraph"
        headingLevel = dict["headingLevel"] as? Int ?? 0
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
    var onFormat: (String) -> Void
    var onFindReplace: () -> Void
    
    var body: some View {
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
                
                // Case sensitive toggle
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
