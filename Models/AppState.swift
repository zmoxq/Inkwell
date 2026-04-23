import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var currentDocument: MarkdownDocument?
    @Published var recentFiles: [FileItem] = []
    @Published var sidebarFiles: [FileItem] = []
    @Published var fileTree: [FileNode] = []
    @Published var currentThemeCSS: String = ""
    @Published var isEditorReady: Bool = false
    @Published var isSidebarVisible: Bool = true
    @Published var sidebarMode: SidebarMode = .files
    @Published var outlineItems: [OutlineItem] = []
    
    /// Set by sidebar outline tap, consumed by editor view to scroll
    @Published var scrollToOutline: OutlineItem? = nil
    
    // MARK: - Theme State
    
    @Published var currentThemeId: String = "inkwell"
    @Published var customThemes: [ThemeInfo] = []
    
    /// All available themes (built-in + custom)
    var allThemes: [ThemeInfo] {
        BuiltInThemes.all + customThemes
    }
    
    var currentTheme: ThemeInfo? {
        allThemes.first { $0.id == currentThemeId }
    }
    
    @Published var workingDirectory: URL? {
        didSet {
            if let dir = workingDirectory {
                loadFilesFromDirectory(dir)
                buildFileTree(from: dir)
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Restore saved theme
        let savedId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? "inkwell"
        self.currentThemeId = savedId
        loadCustomThemesFromDisk()
        applyTheme(id: savedId)
    }
    
    // MARK: - File Tree (hierarchical)
    
    func buildFileTree(from directory: URL) {
        let fm = FileManager.default
        
        // Collect all .md base names at top level for attachment folder detection
        let topLevelMDNames = collectMDBaseNames(in: directory)
        
        fileTree = buildChildren(of: directory, mdNames: topLevelMDNames, rootDir: directory)
    }
    
    private func buildChildren(of directory: URL, mdNames: Set<String>, rootDir: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        // Collect .md base names at this directory level
        let localMDNames = collectMDBaseNames(in: directory)
        
        var nodes: [FileNode] = []
        
        for url in contents {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let modDate = resourceValues?.contentModificationDate
            
            // Skip non-md files
            if !isDirectory && url.pathExtension.lowercased() != "md" {
                continue
            }
            
            // Skip attachment folders (directory name matches a sibling .md file)
            if isDirectory && localMDNames.contains(url.lastPathComponent) {
                continue
            }
            
            if isDirectory {
                let childMDNames = collectMDBaseNames(in: url)
                let children = buildChildren(of: url, mdNames: childMDNames, rootDir: rootDir)
                // Only show directories that contain .md files (directly or nested)
                if !children.isEmpty {
                    let node = FileNode(url: url, isDirectory: true, modificationDate: modDate, children: children, isExpanded: true)
                    nodes.append(node)
                }
            } else {
                let node = FileNode(url: url, isDirectory: false, modificationDate: modDate)
                nodes.append(node)
            }
        }
        
        // Sort: directories first, then by name
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    
    private func collectMDBaseNames(in directory: URL) -> Set<String> {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        var names: Set<String> = []
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir && url.pathExtension.lowercased() == "md" {
                names.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        return names
    }
    
    // MARK: - Flat file list (kept for compatibility)
    
    func loadFilesFromDirectory(_ directory: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var items: [FileItem] = []
        var mdFileNames: Set<String> = []
        var allURLs: [(URL, Bool, Date?)] = []
        
        while let url = enumerator.nextObject() as? URL {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            if !isDirectory && url.pathExtension.lowercased() == "md" {
                mdFileNames.insert(url.deletingPathExtension().lastPathComponent)
            }
            allURLs.append((url, isDirectory, resourceValues?.contentModificationDate))
        }
        
        for (url, isDirectory, modDate) in allURLs {
            if !isDirectory && url.pathExtension.lowercased() != "md" { continue }
            if isDirectory && mdFileNames.contains(url.lastPathComponent) { continue }
            items.append(FileItem(url: url, isDirectory: isDirectory, modificationDate: modDate))
        }
        
        sidebarFiles = items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    
    // MARK: - Document Operations
    
    func openFile(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            currentDocument = MarkdownDocument(url: url, content: content)
            updateOutline(from: content)
            addToRecent(url)
        } catch {
            print("[Inkwell] Error opening file: \(error.localizedDescription)")
        }
    }
    
    func saveCurrentDocument() {
        guard let doc = currentDocument else { return }
        do {
            try doc.content.write(to: doc.url, atomically: true, encoding: .utf8)
            doc.isDirty = false
        } catch {
            print("[Inkwell] Error saving file: \(error.localizedDescription)")
        }
    }
    
    func createNewFile(in directory: URL, name: String = "Untitled.md") -> URL? {
        let fileURL = directory.appendingPathComponent(name)
        let fm = FileManager.default
        var finalURL = fileURL
        var counter = 1
        while fm.fileExists(atPath: finalURL.path) {
            let baseName = name.replacingOccurrences(of: ".md", with: "")
            finalURL = directory.appendingPathComponent("\(baseName) \(counter).md")
            counter += 1
        }
        do {
            try "".write(to: finalURL, atomically: true, encoding: .utf8)
            if let dir = workingDirectory {
                loadFilesFromDirectory(dir)
                buildFileTree(from: dir)
            }
            openFile(finalURL)
            return finalURL
        } catch {
            print("[Inkwell] Error creating file: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func addToRecent(_ url: URL) {
        recentFiles.removeAll { $0.url == url }
        recentFiles.insert(FileItem(url: url, isDirectory: false, modificationDate: Date()), at: 0)
        if recentFiles.count > 20 { recentFiles = Array(recentFiles.prefix(20)) }
    }
    
    // MARK: - Outline
    
    func updateOutline(from markdown: String) {
        outlineItems = OutlineParser.parse(markdown)
    }
    
    // MARK: - Theme
    
    func applyTheme(id: String) {
        currentThemeId = id
        UserDefaults.standard.set(id, forKey: "selectedThemeId")
        
        if let theme = allThemes.first(where: { $0.id == id }) {
            currentThemeCSS = theme.css
        } else {
            currentThemeCSS = BuiltInThemes.inkwell.css
        }
    }
    
    func loadDefaultTheme() {
        applyTheme(id: "inkwell")
    }
    
    func loadCustomCSS(from url: URL) {
        do {
            let css = try String(contentsOf: url, encoding: .utf8)
            let name = url.deletingPathExtension().lastPathComponent
            let id = "custom-\(name)-\(UUID().uuidString.prefix(6))"
            
            // Try to extract colors from CSS for preview swatches
            let bg = extractCSSVar(css, name: "--bg-primary") ?? "#FFFFFF"
            let text = extractCSSVar(css, name: "--text-primary") ?? "#000000"
            let accent = extractCSSVar(css, name: "--accent") ?? "#0066CC"
            
            let theme = ThemeInfo(
                id: id, name: name,
                bg: bg.replacingOccurrences(of: "#", with: ""),
                text: text.replacingOccurrences(of: "#", with: ""),
                accent: accent.replacingOccurrences(of: "#", with: ""),
                css: BuiltInThemes.baseCSS + css,
                isBuiltIn: false
            )
            
            customThemes.append(theme)
            saveCustomThemeToDisk(theme, originalURL: url)
            applyTheme(id: id)
        } catch {
            print("[Inkwell] Error loading CSS: \(error.localizedDescription)")
        }
    }
    
    func removeCustomTheme(_ theme: ThemeInfo) {
        customThemes.removeAll { $0.id == theme.id }
        // Remove from disk
        let dir = customThemesDirectory
        let file = dir.appendingPathComponent("\(theme.id).css")
        try? FileManager.default.removeItem(at: file)
        
        if currentThemeId == theme.id {
            applyTheme(id: "inkwell")
        }
    }
    
    // MARK: - Custom Theme Persistence
    
    private var customThemesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Inkwell/Themes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func saveCustomThemeToDisk(_ theme: ThemeInfo, originalURL: URL) {
        let dir = customThemesDirectory
        let dest = dir.appendingPathComponent("\(theme.id).css")
        try? FileManager.default.copyItem(at: originalURL, to: dest)
        
        // Save metadata
        let meta: [String: String] = ["id": theme.id, "name": theme.name]
        let metaURL = dir.appendingPathComponent("\(theme.id).json")
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL)
        }
    }
    
    private func loadCustomThemesFromDisk() {
        let dir = customThemesDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        
        let cssFiles = files.filter { $0.pathExtension == "css" }
        for cssURL in cssFiles {
            guard let css = try? String(contentsOf: cssURL, encoding: .utf8) else { continue }
            let id = cssURL.deletingPathExtension().lastPathComponent
            
            // Load metadata
            let metaURL = dir.appendingPathComponent("\(id).json")
            var name = id
            if let metaData = try? Data(contentsOf: metaURL),
               let meta = try? JSONDecoder().decode([String: String].self, from: metaData),
               let n = meta["name"] {
                name = n
            }
            
            let bg = extractCSSVar(css, name: "--bg-primary") ?? "#FFFFFF"
            let text = extractCSSVar(css, name: "--text-primary") ?? "#000000"
            let accent = extractCSSVar(css, name: "--accent") ?? "#0066CC"
            
            let theme = ThemeInfo(
                id: id, name: name,
                bg: bg.replacingOccurrences(of: "#", with: ""),
                text: text.replacingOccurrences(of: "#", with: ""),
                accent: accent.replacingOccurrences(of: "#", with: ""),
                css: BuiltInThemes.baseCSS + css,
                isBuiltIn: false
            )
            customThemes.append(theme)
        }
    }
    
    private func extractCSSVar(_ css: String, name: String) -> String? {
        // Match patterns like: --bg-primary: #FDFBF7;
        let pattern = "\(name):\\s*(#[0-9A-Fa-f]{3,8})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: css, range: NSRange(css.startIndex..., in: css)),
              let range = Range(match.range(at: 1), in: css)
        else { return nil }
        return String(css[range])
    }
}
