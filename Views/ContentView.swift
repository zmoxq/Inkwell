import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingContent: String = ""
    @State private var selectedFile: FileItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // Phase 2: Editor enhancement state
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
                // Clear after a short delay to allow re-tapping same item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.scrollToOutline = nil
                }
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
                // Format toolbar
                EditorToolbarView(
                    formatState: formatState,
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
                    }
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
            .navigationTitle(doc.url.deletingPathExtension().lastPathComponent)
            #if os(macOS)
            .navigationSubtitle(doc.isDirty ? "Edited" : "")
            #endif
            .ignoresSafeArea(.keyboard)
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
                Button("Open Folder") {
                    openFolder()
                }
                .buttonStyle(.bordered)
                
                Button("New File") {
                    createNewFile()
                }
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
    
    private func openFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md")!]
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                openFileAndLoadContent(url)
            }
        }
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
}
