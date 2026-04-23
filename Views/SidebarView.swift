import SwiftUI
import Combine

// MARK: - Typora-style Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedFile: FileItem?
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    
    // Typora's accent color (teal/green)
    private let accentTeal = Color(red: 0.31, green: 0.78, blue: 0.65) // #4FC7A5
    
    var body: some View {
        VStack(spacing: 0) {
            topBar
            
            // Main content
            if appState.sidebarMode == .files {
                fileTreeContent
            } else {
                outlineContent
            }
            
            bottomBar
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }
    
    // MARK: - Top Bar (FILES / OUTLINE title, toggle + search)
    
    private var topBar: some View {
        VStack(spacing: 0) {
            if isSearching {
                // Search mode
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    
                    Button(action: {
                        searchText = ""
                        isSearching = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            } else {
                // Normal mode: toggle | TITLE | search
                HStack {
                    // Toggle file/outline (single icon)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.sidebarMode = appState.sidebarMode == .files ? .outline : .files
                        }
                    }) {
                        Image(systemName: appState.sidebarMode == .files ? "list.bullet" : "doc.text")
                            .font(.system(size: 14))
                            .foregroundStyle(.primary.opacity(0.6))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(appState.sidebarMode == .files ? "Switch to Outline" : "Switch to Files")
                    
                    Spacer()
                    
                    // Title
                    Text(appState.sidebarMode == .files ? "FILES" : "OUTLINE")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.primary.opacity(0.7))
                    
                    Spacer()
                    
                    // Search button (files mode only)
                    if appState.sidebarMode == .files {
                        Button(action: { isSearching = true }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.6))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Placeholder for alignment
                        Spacer().frame(width: 24)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            
            // Subtle separator
            Rectangle()
                .fill(.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }
    
    // MARK: - File Tree Content
    
    @ViewBuilder
    private var fileTreeContent: some View {
        if appState.fileTree.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredTree) { node in
                        TyporaFileRow(
                            node: node,
                            selectedFile: $selectedFile,
                            accentColor: accentTeal,
                            depth: 0
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
    }
    
    private var filteredTree: [FileNode] {
        if searchText.isEmpty { return appState.fileTree }
        return filterTree(appState.fileTree, query: searchText)
    }
    
    private func filterTree(_ nodes: [FileNode], query: String) -> [FileNode] {
        var results: [FileNode] = []
        for node in nodes {
            if node.isDirectory {
                let filtered = filterTree(node.children, query: query)
                if !filtered.isEmpty {
                    results.append(FileNode(url: node.url, isDirectory: true, modificationDate: node.modificationDate, children: filtered, isExpanded: true))
                }
            } else if node.name.localizedCaseInsensitiveContains(query) {
                results.append(node)
            }
        }
        return results
    }
    
    // MARK: - Outline Content
    
    @ViewBuilder
    private var outlineContent: some View {
        if appState.outlineItems.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text(appState.currentDocument == nil ? "No document open" : "No headings")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appState.outlineItems) { item in
                        TyporaOutlineRow(item: item, accentColor: accentTeal)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No folder open")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Button("Open Folder") { openFolder() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.primary.opacity(0.06))
                .frame(height: 0.5)
            
            HStack(spacing: 0) {
                // + New file
                Button(action: {
                    if let dir = appState.workingDirectory {
                        let _ = appState.createNewFile(in: dir)
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.5))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(appState.workingDirectory == nil)
                
                Spacer()
                
                // Folder name
                if let dir = appState.workingDirectory {
                    Text(dir.lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.5))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // More menu
                Menu {
                    Button("Open Folder...", action: openFolder)
                    Divider()
                    Button("Expand All") { setExpandedAll(true) }
                    Button("Collapse All") { setExpandedAll(false) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            .padding(.horizontal, 6)
            .frame(height: 32)
        }
    }
    
    // MARK: - Actions
    
    private func openFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                appState.workingDirectory = url
            }
        }
        #else
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        appState.workingDirectory = documentsURL
        #endif
    }
    
    private func setExpandedAll(_ expanded: Bool) {
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isDirectory {
                    node.isExpanded = expanded
                    walk(node.children)
                }
            }
        }
        walk(appState.fileTree)
        appState.objectWillChange.send()
    }
}

// MARK: - Typora File Row (recursive tree node)

struct TyporaFileRow: View {
    @ObservedObject var node: FileNode
    @Binding var selectedFile: FileItem?
    let accentColor: Color
    let depth: Int
    
    private var isSelected: Bool {
        guard let sel = selectedFile else { return false }
        return sel.url == node.url
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row
            HStack(spacing: 0) {
                // Left accent bar for selected file
                if isSelected && !node.isDirectory {
                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 3)
                } else {
                    Spacer().frame(width: 3)
                }
                
                // Indent
                Spacer().frame(width: CGFloat(depth) * 20 + 10)
                
                // Folder icon (with color for selected/expanded) or file icon
                if node.isDirectory {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? accentColor : .primary.opacity(0.7))
                        .frame(width: 20)
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.45))
                        .frame(width: 20)
                }
                
                // Name
                Text(node.displayName)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.leading, 8)
                
                Spacer()
            }
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(
                // Selected file: light gray background spanning full width
                isSelected && !node.isDirectory
                    ? Color.primary.opacity(0.05)
                    : Color.clear
            )
            .onTapGesture {
                if node.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        node.isExpanded.toggle()
                    }
                } else {
                    selectedFile = FileItem(
                        url: node.url,
                        isDirectory: false,
                        modificationDate: node.modificationDate
                    )
                }
            }
            
            // Children
            if node.isDirectory && node.isExpanded {
                ForEach(node.children) { child in
                    TyporaFileRow(
                        node: child,
                        selectedFile: $selectedFile,
                        accentColor: accentColor,
                        depth: depth + 1
                    )
                }
            }
        }
    }
}

// MARK: - Typora Outline Row

struct TyporaOutlineRow: View {
    let item: OutlineItem
    let accentColor: Color
    @EnvironmentObject var appState: AppState
    
    private var isSelected: Bool {
        appState.scrollToOutline?.id == item.id
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar for selected item
            Rectangle()
                .fill(isSelected ? accentColor : Color.clear)
                .frame(width: 3)
            
            Spacer().frame(width: CGFloat(item.level - 1) * 18 + 13)
            
            Text(item.displayTitle)
                .font(.system(size: item.level == 1 ? 14 : 13, weight: item.level <= 2 ? .medium : .regular))
                .foregroundStyle(Color.primary.opacity(isSelected ? 1.0 : (item.level == 1 ? 1.0 : 0.6)))
                .lineLimit(1)
            
            Spacer()
        }
        .frame(height: 30)
        .background(Color.primary.opacity(isSelected ? 0.05 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            appState.scrollToOutline = item
        }
    }
}
