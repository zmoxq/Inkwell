import SwiftUI
import Combine

// MARK: - MarkdownDocument

class MarkdownDocument: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    @Published var content: String
    @Published var isDirty: Bool = false
    
    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
    
    var fileName: String {
        url.lastPathComponent
    }
    
    var attachmentsDirectory: URL {
        url.deletingPathExtension()
    }
    
    init(url: URL, content: String) {
        self.url = url
        self.content = content
    }
    
    func ensureAttachmentsDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: attachmentsDirectory.path) {
            try fm.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        }
    }
    
    func saveAttachment(data: Data, fileName: String) throws -> String {
        try ensureAttachmentsDirectory()
        let fm = FileManager.default
        var finalName = fileName
        var targetURL = attachmentsDirectory.appendingPathComponent(finalName)
        var counter = 1
        while fm.fileExists(atPath: targetURL.path) {
            let ext = (fileName as NSString).pathExtension
            let base = (fileName as NSString).deletingPathExtension
            finalName = "\(base)_\(counter).\(ext)"
            targetURL = attachmentsDirectory.appendingPathComponent(finalName)
            counter += 1
        }
        try data.write(to: targetURL)
        return "\(name)/\(finalName)"
    }
}

// MARK: - FileNode (Tree structure for sidebar)

/// A node in the file tree. Can be a directory (with children) or a file (leaf).
class FileNode: Identifiable, ObservableObject, Hashable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let modificationDate: Date?
    @Published var children: [FileNode]
    @Published var isExpanded: Bool
    
    var name: String { url.lastPathComponent }
    
    var displayName: String {
        isDirectory ? name : name.replacingOccurrences(of: ".md", with: "")
    }
    
    var icon: String {
        if isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        return "doc.text"
    }
    
    init(url: URL, isDirectory: Bool, modificationDate: Date? = nil, children: [FileNode] = [], isExpanded: Bool = false) {
        self.url = url
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
        self.children = children
        self.isExpanded = isExpanded
    }
    
    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

// MARK: - FileItem (kept for compatibility)

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let modificationDate: Date?
    
    var name: String { url.lastPathComponent }
    var icon: String { isDirectory ? "folder.fill" : "doc.text" }
    
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
}

// MARK: - OutlineItem

/// Represents a heading extracted from the current markdown document.
struct OutlineItem: Identifiable, Equatable {
    let id = UUID()
    let level: Int      // 1-6
    let title: String
    let line: Int       // line number in the markdown source
    let numberPrefix: String  // e.g. "1.", "1.1", "1.1.2"
    
    /// Indentation based on heading level
    var indent: CGFloat {
        CGFloat(level - 1) * 16
    }
    
    /// Display title with number prefix
    var displayTitle: String {
        numberPrefix.isEmpty ? title : "\(numberPrefix) \(title)"
    }
}

// MARK: - Outline Parser

struct OutlineParser {
    /// Extract headings from markdown text with auto-numbering.
    /// H1 has no number, H2 starts "1.", H3 = "1.1", etc.
    static func parse(_ markdown: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        
        // Counters: h2=0, h3=0, h4=0, h5=0, h6=0
        var counters = [0, 0, 0, 0, 0]  // index 0=h2, 1=h3, 2=h4, 3=h5, 4=h6
        
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock { continue }
            
            if let match = line.range(of: #"^(#{1,6})\s+(.+)"#, options: .regularExpression) {
                let fullMatch = String(line[match])
                let hashPart = fullMatch.prefix(while: { $0 == "#" })
                let level = hashPart.count
                let title = String(fullMatch.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                
                var numberPrefix = ""
                
                if level == 1 {
                    // H1: no number, reset all counters
                    counters = [0, 0, 0, 0, 0]
                } else if level >= 2 && level <= 6 {
                    let idx = level - 2  // h2=0, h3=1, h4=2, h5=3, h6=4
                    counters[idx] += 1
                    // Reset all lower-level counters
                    for i in (idx + 1)..<counters.count {
                        counters[i] = 0
                    }
                    // Build prefix: "1." for h2, "1.1" for h3, "1.1.2" for h4, etc.
                    var parts: [String] = []
                    for i in 0...idx {
                        parts.append(String(counters[i]))
                    }
                    numberPrefix = parts.joined(separator: ".")
                    if level == 2 {
                        numberPrefix += "."  // h2: "1." to match Typora style
                    }
                }
                
                items.append(OutlineItem(level: level, title: title, line: index, numberPrefix: numberPrefix))
            }
        }
        
        return items
    }
}

// MARK: - Sidebar Mode

enum SidebarMode {
    case files
    case outline
}

// MARK: - FormatCommand

enum FormatCommand: String {
    case bold, italic, strikethrough
    case heading1, heading2, heading3
    case bulletList, orderedList, taskList
    case codeBlock, blockquote
    case horizontalRule
    case link, image
}
