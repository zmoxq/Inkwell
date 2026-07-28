import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var openTabs: [MarkdownDocument] = []
    @Published var activeTabId: UUID? = nil
    @Published var recentFiles: [FileItem] = []
    @Published var sidebarFiles: [FileItem] = []
    @Published var fileTree: [FileNode] = []
    @Published var currentThemeCSS: String = ""
    @Published var isEditorReady: Bool = false
    // Undo/redo availability for the ACTIVE editor, pushed from JS on stack
    // change (§11.8). Drives the Edit-menu item enabled state. Best-effort:
    // the JS keydown handler is the real workhorse, so stale enablement never
    // breaks undo — it only greys the menu item.
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    @Published var isSidebarVisible: Bool = true
    @Published var sidebarMode: SidebarMode = .files
    @Published var outlineItems: [OutlineItem] = []
    
    /// Set by sidebar outline tap, consumed by editor view to scroll
    @Published var scrollToOutline: OutlineItem? = nil
    
    /// The currently active document (computed from activeTabId)
    var currentDocument: MarkdownDocument? {
        guard let id = activeTabId else { return nil }
        return openTabs.first { $0.id == id }
    }
    
    /// Editor zoom level (50–200, default 100)
    @Published var zoomLevel: Int = 100
    
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
    
    /// Non-nil when restoring the last library at launch failed (bookmark
    /// unresolvable or access denied). Surfaced in the empty state as a distinct
    /// message so a failed restore never silently looks like a plain empty
    /// sidebar — which would be confusable with KI-1. Cleared on a successful
    /// openLibrary. (PHASE_5A §二, constraint #1)
    @Published var libraryReopenError: String? = nil

    @Published var workingDirectory: URL? {
        didSet {
            if let dir = workingDirectory {
                loadFilesFromDirectory(dir)
                buildFileTree(from: dir)
                scanForOrphanSidecars(in: dir)
            }
        }
    }

    /// Orphan-sidecar recovery on library open (§2). Runs off the main
    /// thread; results are log-only and sidecars never appear in the file
    /// tree, so no UI refresh is needed.
    private func scanForOrphanSidecars(in directory: URL) {
        DispatchQueue.global(qos: .utility).async {
            let result = OrphanSidecarScanner.scan(libraryRoot: directory)
            for pair in result.rebound {
                print("[Inkwell] Rebound orphan sidecar: \(pair.orphan.lastPathComponent) -> \(pair.destination.lastPathComponent)")
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Library security scope (PHASE_5A §二)
    /// The single security-scoped URL currently being accessed (the open library
    /// root). Exactly one is held at a time; switching libraries stops the
    /// previous before starting the new — strict start/stop pairing, since an
    /// unbalanced start leaks a sandbox extension (constraint #2).
    private var accessedSecurityScopedURL: URL?
    private static let libraryBookmarkKey = "libraryBookmark"

    init() {
        // Restore saved theme
        let savedId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? "inkwell"
        self.currentThemeId = savedId
        loadCustomThemesFromDisk()
        applyTheme(id: savedId)
        
        // Restore saved zoom level
        let savedZoom = UserDefaults.standard.integer(forKey: "editorZoomLevel")
        self.zoomLevel = savedZoom > 0 ? savedZoom : 100

        #if os(macOS)
        // App-quit flush (macOS): scenePhase does not reliably reach .background
        // before termination, so hook willTerminate explicitly to write out any
        // dirty tabs. Silent — no "save changes?" prompt this round. iOS relies
        // on the scenePhase .background flush instead (kill-from-background gives
        // no further callback, so .background is the last chance). App-lifetime
        // singleton, so the observer is intentionally never removed.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushDirtyDocuments()
            // Release the library security scope on quit (pairing tidy-up; the
            // OS reclaims on exit regardless).
            self?.accessedSecurityScopedURL?.stopAccessingSecurityScopedResource()
        }
        #endif

        // Restore the last-opened library (security-scoped bookmark). Runs after
        // the observer is registered; sets workingDirectory (whose didSet loads
        // the tree) only once access is active. (PHASE_5A §二)
        restoreLibrary()
    }
    
    // MARK: - File Tree (hierarchical)
    
    func buildFileTree(from directory: URL) {
        _ = FileManager.default
        
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
        // If already open in a tab, just switch to it
        if let existing = openTabs.first(where: { $0.url == url }) {
            activeTabId = existing.id
            updateOutline(from: existing.content)
            return
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let doc = MarkdownDocument(url: url, content: content)
            openTabs.append(doc)
            activeTabId = doc.id
            updateOutline(from: content)
            addToRecent(url)
        } catch {
            print("[Inkwell] Error opening file: \(error.localizedDescription)")
        }
    }
    
    func closeTab(_ docId: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == docId }) else { return }
        
        // Save if dirty before closing
        let doc = openTabs[idx]
        if doc.isDirty {
            try? NoteFileOperations.saveNote(content: doc.content, to: doc.url)
        }
        
        openTabs.remove(at: idx)
        
        // Update active tab
        if activeTabId == docId {
            if openTabs.isEmpty {
                activeTabId = nil
            } else {
                // Activate the nearest tab
                let newIdx = min(idx, openTabs.count - 1)
                activeTabId = openTabs[newIdx].id
                if let newDoc = openTabs[safe: newIdx] {
                    updateOutline(from: newDoc.content)
                }
            }
        }
    }
    
    func closeOtherTabs(except docId: UUID) {
        let toClose = openTabs.filter { $0.id != docId }
        for doc in toClose {
            if doc.isDirty {
                try? NoteFileOperations.saveNote(content: doc.content, to: doc.url)
            }
        }
        openTabs.removeAll { $0.id != docId }
        activeTabId = docId
    }
    
    func closeAllTabs() {
        for doc in openTabs {
            if doc.isDirty {
                try? NoteFileOperations.saveNote(content: doc.content, to: doc.url)
            }
        }
        openTabs.removeAll()
        activeTabId = nil
    }
    
    func saveCurrentDocument() {
        guard let doc = currentDocument else { return }
        do {
            try NoteFileOperations.saveNote(content: doc.content, to: doc.url)
            doc.isDirty = false
        } catch {
            print("[Inkwell] Error saving file: \(error.localizedDescription)")
        }
    }

    // MARK: - Source-of-truth flush (lifecycle hooks)
    //
    // Disk writes used to be bound to Cmd+S / tab close / rename only, so
    // in-memory edits could outlive the app without ever reaching disk (the
    // memory↔disk inconsistency window had no upper bound). These flush entry
    // points close that gap for scenePhase changes, app termination and tab
    // switches. Each is gated on `isDirty`; because the tab stays open, a
    // successful write resets `isDirty` so an unchanged tab never incurs a
    // redundant write on the next flush.

    /// Flush every open document that has unsaved changes. Called from lifecycle
    /// hooks (scenePhase background/inactive, app termination).
    func flushDirtyDocuments() {
        for doc in openTabs where doc.isDirty {
            flush(doc)
        }
    }

    /// Flush a single open document by id, if dirty. Called when switching away
    /// from a tab (flushes the outgoing tab).
    func flushDocument(id: UUID) {
        guard let doc = openTabs.first(where: { $0.id == id }), doc.isDirty else { return }
        flush(doc)
    }

    private func flush(_ doc: MarkdownDocument) {
        do {
            try NoteFileOperations.saveNote(content: doc.content, to: doc.url)
            doc.isDirty = false
        } catch {
            print("[Inkwell] Error flushing \(doc.url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Library (folder) open + bookmark persistence (PHASE_5A §二)

    /// Open a user-picked folder as the library: persist a security-scoped
    /// bookmark, take access, and set it as the working directory. Call sites:
    /// macOS NSOpenPanel completions and the iOS FolderPickerPresenter callback.
    func openLibrary(pickedURL: URL) {
        // iOS picker URLs must be accessed before they can even be read to build
        // a bookmark (harmless on macOS, where panel URLs return false). This
        // access is only for bookmark creation and is released immediately; the
        // session-long access is taken separately in activateLibrary.
        let tempAccess = pickedURL.startAccessingSecurityScopedResource()
        defer { if tempAccess { pickedURL.stopAccessingSecurityScopedResource() } }

        do {
            let data = try SecurityScopedBookmark.create(from: pickedURL)
            UserDefaults.standard.set(data, forKey: Self.libraryBookmarkKey)
        } catch {
            // Persistence failed, but the folder still opens for this session.
            print("[Inkwell] Could not persist library bookmark: \(error.localizedDescription)")
        }

        libraryReopenError = nil
        activateLibrary(url: pickedURL)
    }

    /// Restore the last-opened library from its bookmark at launch. On failure
    /// this does NOT silently leave an empty sidebar (which would be confusable
    /// with KI-1) — it sets a distinct libraryReopenError guiding the user to
    /// re-pick, and keeps the bookmark (a temporarily-unavailable folder can
    /// recover on a later launch; re-picking overwrites it). (constraint #1)
    private func restoreLibrary() {
        guard let data = UserDefaults.standard.data(forKey: Self.libraryBookmarkKey) else { return }

        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try SecurityScopedBookmark.resolve(data)
        } catch {
            libraryReopenError = "Couldn't reopen your last folder — it may have moved or been removed. Open a folder to continue."
            return
        }

        guard resolved.url.startAccessingSecurityScopedResource() else {
            libraryReopenError = "Couldn't reopen your last folder — access wasn't granted. Open a folder to continue."
            return
        }
        accessedSecurityScopedURL = resolved.url

        // isStale self-heal: regenerate + persist while access is active, rather
        // than failing (constraint #1).
        if resolved.isStale, let fresh = try? SecurityScopedBookmark.create(from: resolved.url) {
            UserDefaults.standard.set(fresh, forKey: Self.libraryBookmarkKey)
        }

        workingDirectory = resolved.url  // didSet loads the tree (scope is active)
    }

    /// Take session-long security-scoped access to `url` and make it the working
    /// directory. Strict pairing: releases the previously accessed URL first, so
    /// at most one scope is held at a time (constraint #2). On macOS a
    /// freshly-panel-granted URL returns false from startAccessing yet is still
    /// usable this session via the panel grant, so we simply don't track it for
    /// stopAccessing in that case.
    private func activateLibrary(url: URL) {
        if let prev = accessedSecurityScopedURL {
            prev.stopAccessingSecurityScopedResource()
            accessedSecurityScopedURL = nil
        }
        if url.startAccessingSecurityScopedResource() {
            accessedSecurityScopedURL = url
        }
        workingDirectory = url
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
    
    // MARK: - File management (rename / delete)

    /// Renames a note in place (same directory). Returns the new URL.
    ///
    /// Ordering: unsaved changes are saved to the OLD path first, then the
    /// pair is moved. Disk state is complete before the move, the sidecar
    /// contentHash recorded at save matches the bytes being moved, and a
    /// failed move leaves everything intact at the old path.
    @discardableResult
    func renameNote(at url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return url }
        let fileName = trimmed.lowercased().hasSuffix(".md") ? trimmed : trimmed + ".md"
        let destination = url.deletingLastPathComponent().appendingPathComponent(fileName)
        guard destination != url else { return url }

        let openDoc = openTabs.first { $0.url == url }
        if let doc = openDoc, doc.isDirty {
            try NoteFileOperations.saveNote(content: doc.content, to: url)
            doc.isDirty = false
        }
        try NoteFileOperations.renameNote(from: url, to: destination)
        openDoc?.url = destination
        refreshFileTree()
        return destination
    }

    /// Moves a note (and its sidecar) to the trash and closes its tab if
    /// open — discarding unsaved changes, since saving them would resurrect
    /// the file at the path just trashed.
    func deleteNote(at url: URL) throws {
        try NoteFileOperations.trashNote(at: url)
        if let idx = openTabs.firstIndex(where: { $0.url == url }) {
            let doc = openTabs[idx]
            openTabs.remove(at: idx)
            if activeTabId == doc.id {
                if openTabs.isEmpty {
                    activeTabId = nil
                } else {
                    let newIdx = min(idx, openTabs.count - 1)
                    activeTabId = openTabs[newIdx].id
                    updateOutline(from: openTabs[newIdx].content)
                }
            }
        }
        refreshFileTree()
    }

    private func refreshFileTree() {
        if let dir = workingDirectory {
            loadFilesFromDirectory(dir)
            buildFileTree(from: dir)
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
    
    // MARK: - Zoom
    
    func setZoom(_ level: Int) {
        zoomLevel = max(50, min(200, level))
        UserDefaults.standard.set(zoomLevel, forKey: "editorZoomLevel")
    }
    
    func zoomIn() {
        setZoom(zoomLevel + 10)
    }
    
    func zoomOut() {
        setZoom(zoomLevel - 10)
    }
    
    func zoomReset() {
        setZoom(100)
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

// MARK: - Safe Array Subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
