import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingContent: String = ""
    @State private var selectedFile: FileItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    @StateObject private var formatState = EditorFormatState()
    @StateObject private var findReplaceState = FindReplaceState()
    @State private var editorCoordinator: EditorCoordinator?
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedFile: $selectedFile)
                .environmentObject(appState)
        } detail: {
            editorArea
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        .focusable(false)
        #endif
        .onChange(of: selectedFile) { _, newFile in
            if let file = newFile, !file.isDirectory {
                openFileAndLoadContent(file.url)
            }
        }
        .onChange(of: appState.isSidebarVisible) { _, visible in
            columnVisibility = visible ? .all : .detailOnly
        }
        .onChange(of: appState.scrollToOutline) { _, item in
            if let item = item {
                editorCoordinator?.scrollToHeading(title: item.title, level: item.level)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.scrollToOutline = nil
                }
            }
        }
        .onChange(of: appState.activeTabId) { _, _ in
            if let doc = appState.currentDocument {
                editingContent = doc.content
            }
        }
        .onAppear {
            if let doc = appState.currentDocument {
                editingContent = doc.content
            }
        }
    }
    
    // MARK: - Open File
    
    private func openFileAndLoadContent(_ url: URL) {
        appState.openFile(url)
        editingContent = appState.currentDocument?.content ?? ""
    }
    
    // MARK: - Editor Area
    
    @ViewBuilder
    private var editorArea: some View {
        if let doc = appState.currentDocument {
            VStack(spacing: 0) {
                // Tab bar (only shows when multiple tabs open)
                TabBarView()
                    .environmentObject(appState)
                
                // Format toolbar
                EditorToolbarView(
                    formatState: formatState,
                    zoomLevel: appState.zoomLevel,
                    onFormat: { command in
                        editorCoordinator?.execFormat(command)
                    },
                    onFindReplace: {
                        if findReplaceState.isVisible {
                            editorCoordinator?.closeFindReplace()
                            findReplaceState.isVisible = false
                        } else {
                            findReplaceState.isVisible = true
                        }
                    },
                    onToggleTOC: {
                        editorCoordinator?.toggleTOC()
                    },
                    onZoomTo: { level in setZoom(level) },
                    onExportHTML: { exportHTML(doc: doc) },
                    onExportPDF: { exportPDF(doc: doc) }
                )
                
                // Find & Replace bar
                if findReplaceState.isVisible {
                    FindReplaceBar(
                        state: findReplaceState,
                        onFind: { query, caseSensitive in
                            editorCoordinator?.findInDocument(query, caseSensitive: caseSensitive)
                        },
                        onFindNext: {
                            editorCoordinator?.findNext()
                        },
                        onFindPrevious: {
                            editorCoordinator?.findPrevious()
                        },
                        onReplace: { replacement in
                            editorCoordinator?.replaceCurrent(replacement)
                        },
                        onReplaceAll: { replacement in
                            editorCoordinator?.replaceAll(replacement)
                        },
                        onClose: {
                            editorCoordinator?.closeFindReplace()
                        }
                    )
                }
                
                // Editor
                MarkdownEditorView(
                    markdownContent: $editingContent,
                    documentURL: doc.url,
                    onContentChange: { newContent in
                        appState.currentDocument?.content = newContent
                        appState.currentDocument?.isDirty = true
                    },
                    onSaveRequest: {
                        appState.saveCurrentDocument()
                    },
                    onCoordinatorReady: { coordinator in
                        coordinator.formatState = formatState
                        coordinator.findReplaceState = findReplaceState
                        editorCoordinator = coordinator
                    }
                )
                .environmentObject(appState)
            }
            .id(doc.id)
            .navigationTitle(doc.name)
            #if os(macOS)
            .navigationSubtitle(doc.isDirty ? "Edited" : "")
            #endif
            .ignoresSafeArea(.keyboard)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    editorCoordinator?.setZoom(appState.zoomLevel)
                }
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in zoomIn() }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in zoomOut() }
            .onReceive(NotificationCenter.default.publisher(for: .zoomReset)) { _ in zoomReset() }
            #endif
        } else {
            emptyStateView
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("No document open")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text("Open a folder or create a new file to start editing.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button("Open Folder") { openFolder() }
                    .buttonStyle(.bordered)
                
                Button("New File") { createNewFile() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.77, green: 0.38, blue: 0.24))
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    
    private func createNewFile() {
        let directory = appState.workingDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        if let url = appState.createNewFile(in: directory) {
            editingContent = ""
            selectedFile = FileItem(url: url, isDirectory: false, modificationDate: Date())
        }
    }
    
    // MARK: - Zoom
    
    private func setZoom(_ level: Int) {
        appState.setZoom(level)
        editorCoordinator?.setZoom(appState.zoomLevel)
    }
    
    private func zoomIn() { setZoom(appState.zoomLevel + 10) }
    private func zoomOut() { setZoom(appState.zoomLevel - 10) }
    private func zoomReset() { setZoom(100) }
    
    // MARK: - Export
    
    private func exportHTML(doc: MarkdownDocument) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.html]
        panel.nameFieldStringValue = doc.name + ".html"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            editorCoordinator?.exportHTML { html in
                guard let html = html else { return }
                try? html.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }
    
    private func exportPDF(doc: MarkdownDocument) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.nameFieldStringValue = doc.name + ".pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            editorCoordinator?.exportPDF { data in
                guard let data = data else { return }
                try? data.write(to: url)
            }
        }
        #endif
    }
}

// MARK: - Tab Bar

struct TabBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if appState.openTabs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(appState.openTabs) { doc in
                        TabItemView(doc: doc, isActive: doc.id == appState.activeTabId)
                            .onTapGesture {
                                appState.activeTabId = doc.id
                                appState.updateOutline(from: doc.content)
                            }
                            .contextMenu {
                                Button("Close") { appState.closeTab(doc.id) }
                                Button("Close Others") { appState.closeOtherTabs(except: doc.id) }
                                Divider()
                                Button("Close All") { appState.closeAllTabs() }
                            }
                    }
                    Spacer()
                }
            }
            .frame(height: 30)
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(uiColor: .secondarySystemBackground))
            #endif
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

struct TabItemView: View {
    @ObservedObject var doc: MarkdownDocument
    let isActive: Bool
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 4) {
            // Unsaved indicator
            if doc.isDirty {
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 6, height: 6)
            }
            
            Text(doc.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
            
            // Close button
            Button(action: { appState.closeTab(doc.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.primary.opacity(0.06) : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Divider().frame(height: 16)
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Keyboard Shortcut Notifications

#if os(macOS)
extension Notification.Name {
    static let zoomIn = Notification.Name("inkwell.zoomIn")
    static let zoomOut = Notification.Name("inkwell.zoomOut")
    static let zoomReset = Notification.Name("inkwell.zoomReset")
}
#endif
