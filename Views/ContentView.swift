import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedFile: FileItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @StateObject private var formatState = EditorFormatState()
    @StateObject private var findReplaceState = FindReplaceState()

    /// One resident EditorCoordinator per open tab, keyed by MarkdownDocument.id.
    /// Replaces the former single `editorCoordinator` slot (Option A: per-tab
    /// resident editors). Toolbar / find commands target the *active* tab's
    /// coordinator while inactive editors stay alive and hidden.
    @State private var coordinators: [UUID: EditorCoordinator] = [:]

    /// Coordinator for the currently active tab, or nil if no tab is open.
    private var activeCoordinator: EditorCoordinator? {
        guard let id = appState.activeTabId else { return nil }
        return coordinators[id]
    }

    /// A per-tab content binding scoped by document id. Captures only `appState`
    /// (app-lifetime) and the id (a value type) — never `self` or a Coordinator —
    /// because this binding is stored on the EditorCoordinator and any reference
    /// capture here would rebuild the retain chain we just eliminated.
    private func contentBinding(tabId: UUID) -> Binding<String> {
        Binding(
            get: { [appState] in
                appState.openTabs.first(where: { $0.id == tabId })?.content ?? ""
            },
            set: { [appState] newValue in
                guard let doc = appState.openTabs.first(where: { $0.id == tabId }),
                      doc.content != newValue else { return }
                doc.content = newValue
            }
        )
    }
    
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
                activeCoordinator?.scrollToHeading(title: item.title, level: item.level)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.scrollToOutline = nil
                }
            }
        }
        .onChange(of: appState.activeTabId) { _, newId in
            // Resident editors: switching only flips visibility, no rebuild.
            // Move keyboard focus to the newly active editor so typing routes
            // there. Small delay lets a just-opened tab's webView attach to the
            // window before makeFirstResponder. Previous editor resigns
            // automatically, so hidden editors keep no first responder.
            guard let id = newId else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                coordinators[id]?.makeEditorFirstResponder()
            }
        }
        .onChange(of: appState.openTabs.map(\.id)) { _, ids in
            // A tab was closed → drop its coordinator so the EditorCoordinator /
            // WKWebView is released (ForEach already dismantled the view). Also
            // covers the last-tab boundary (dict becomes empty on close-all).
            coordinators = coordinators.filter { ids.contains($0.key) }
        }
    }
    
    // MARK: - Open File
    
    private func openFileAndLoadContent(_ url: URL) {
        // Each resident editor binds to its own document via contentBinding, so
        // there is no shared editing buffer to seed here.
        appState.openFile(url)
    }
    
    // MARK: - Editor Area
    
    @ViewBuilder
    private var editorArea: some View {
        if let activeDoc = appState.currentDocument {
            VStack(spacing: 0) {
                // Tab bar (only shows when multiple tabs open)
                TabBarView()
                    .environmentObject(appState)

                // Format toolbar — chrome shared across tabs; always drives the
                // active tab's editor via activeCoordinator.
                EditorToolbarView(
                    formatState: formatState,
                    zoomLevel: appState.zoomLevel,
                    onFormat: { command in
                        activeCoordinator?.execFormat(command)
                    },
                    onFindReplace: {
                        if findReplaceState.isVisible {
                            activeCoordinator?.closeFindReplace()
                            findReplaceState.isVisible = false
                        } else {
                            findReplaceState.isVisible = true
                        }
                    },
                    onToggleTOC: {
                        activeCoordinator?.toggleTOC()
                    },
                    onZoomTo: { level in setZoom(level) },
                    onExportHTML: { exportHTML(doc: activeDoc) },
                    onExportPDF: { exportPDF(doc: activeDoc) }
                )

                // Find & Replace bar
                if findReplaceState.isVisible {
                    FindReplaceBar(
                        state: findReplaceState,
                        onFind: { query, caseSensitive in
                            activeCoordinator?.findInDocument(query, caseSensitive: caseSensitive)
                        },
                        onFindNext: {
                            activeCoordinator?.findNext()
                        },
                        onFindPrevious: {
                            activeCoordinator?.findPrevious()
                        },
                        onReplace: { replacement in
                            activeCoordinator?.replaceCurrent(replacement)
                        },
                        onReplaceAll: { replacement in
                            activeCoordinator?.replaceAll(replacement)
                        },
                        onClose: {
                            activeCoordinator?.closeFindReplace()
                        }
                    )
                }

                // Tag chip row (Phase 4 PR 4) — reflects the active document
                TagBarView(document: activeDoc)

                // Resident editors: one WKWebView per open tab, kept alive across
                // switches. Identity comes from ForEach over stable tab ids — NOT
                // `.id(doc.id)` — so switching never rebuilds. Only the active tab
                // is visible + interactive; inactive editors are hidden (opacity 0)
                // and non-interactive so no touches/keys leak through. Closing a
                // tab removes it from openTabs → ForEach dismantles that editor →
                // the release path (WeakScriptMessageHandler + dismantle) fires.
                ZStack {
                    ForEach(appState.openTabs) { tab in
                        let isActive = tab.id == appState.activeTabId
                        MarkdownEditorView(
                            markdownContent: contentBinding(tabId: tab.id),
                            documentURL: tab.url,
                            // Stored closures: capture only `appState` (app-lifetime)
                            // and `tab.id` (a value type). Never `self` or a
                            // Coordinator — that daisy chain previously kept every
                            // Coordinator/WKWebView alive.
                            onContentChange: { [appState] newContent in
                                guard let doc = appState.openTabs.first(where: { $0.id == tab.id }) else { return }
                                doc.content = newContent
                                doc.isDirty = true
                            },
                            onSaveRequest: { [appState] in
                                appState.saveCurrentDocument()
                            },
                            onCoordinatorReady: { coordinator in
                                // onCoordinatorReady is NOT stored on the Coordinator
                                // (invoked once in makeNSView, held by the
                                // representable), so it's released with the tab's
                                // identity and does not form a persistent chain.
                                coordinator.formatState = formatState
                                coordinator.findReplaceState = findReplaceState
                                coordinator.setZoom(appState.zoomLevel)
                                coordinators[tab.id] = coordinator
                            }
                        )
                        .environmentObject(appState)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .zIndex(isActive ? 1 : 0)
                    }
                }
            }
            .navigationTitle(activeDoc.name)
            #if os(macOS)
            .navigationSubtitle(activeDoc.isDirty ? "Edited" : "")
            #endif
            .ignoresSafeArea(.keyboard)
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
            selectedFile = FileItem(url: url, isDirectory: false, modificationDate: Date())
        }
    }
    
    // MARK: - Zoom
    
    private func setZoom(_ level: Int) {
        appState.setZoom(level)
        activeCoordinator?.setZoom(appState.zoomLevel)
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
            activeCoordinator?.exportHTML { html in
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
            activeCoordinator?.exportPDF { data in
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
