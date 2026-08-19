import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedFile: FileItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    // KI-1 (transitional, Phase 5A): in compact width NavigationSplitView shows a
    // single column chosen by preferredCompactColumn (NOT columnVisibility, which
    // only governs regular width). Opening a file flips this to .detail so the
    // editor pages over; back-to-list is the system-provided back button.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

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
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
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
        .onChange(of: appState.editorRevealTick) { _, _ in
            // KI-1 (transitional): a file row was tapped — page to the editor in
            // compact width. Driven by a per-tap tick, NOT selectedFile (url-
            // equatable, so re-tapping the active file doesn't change it) nor
            // activeTabId (unchanged when re-tapping the active tab). Ignored in
            // regular width. See PHASE_5A §一 / KNOWN_ISSUES KI-1.
            preferredCompactColumn = .detail
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
        .onChange(of: appState.activeTabId) { oldId, newId in
            // Resident editors: switching only flips visibility, no rebuild.
            // Snapshot the outgoing editor's caret now, while it still holds a
            // valid selection (before we move first responder away from it), so
            // it can be restored when the user returns to that tab.
            if let old = oldId {
                coordinators[old]?.snapshotSelection()
                // Source-of-truth flush of the OUTGOING tab. Its content is
                // already mirrored into the document by the contentChange bridge
                // on every input, so this writes that in-memory content to disk
                // (no-op when the tab has no unsaved changes).
                appState.flushDocument(id: old)
            }
            // Move keyboard focus to the newly active editor so typing routes
            // there (focus() also restores that editor's snapshotted caret).
            // Small delay lets a just-opened tab's webView attach to the window
            // before makeFirstResponder. Previous editor resigns automatically,
            // so hidden editors keep no first responder.
            guard let id = newId else { return }
            // KI-1 — TRANSITIONAL (Phase 5A, method A). See
            // PHASE_5A_IOS_ENABLEMENT.md §一 and KNOWN_ISSUES.md KI-1. In compact
            // width NavigationSplitView shows one column at a time, and because
            // the sidebar is a hand-drawn ScrollView + onTapGesture (not
            // List(selection:)) the system does NOT auto-advance to the detail
            // column when a document opens. So whenever a tab becomes active we
            // page to .detail to reveal the editor — this covers both tapping an
            // existing file (-> selectedFile -> openFile) and creating a new one
            // (sidebar "+" -> createNewFile -> openFile), which both land on
            // activeTabId. (preferredCompactColumn only affects compact; regular
            // width ignores it and keeps both columns.) This is the stage-1
            // minimal fix, NOT the final navigation form — whether to adopt a
            // NavigationSplitView-managed List(selection:) is deferred to the
            // Phase 5 iOS shell design.
            preferredCompactColumn = .detail
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                coordinators[id]?.makeEditorFirstResponder()
            }
            // Refresh Edit-menu enablement from the newly active editor (§11.8);
            // the stack only pushes on change, so pull its current state now.
            coordinators[id]?.refreshUndoState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .inkwellUndo)) { _ in
            activeCoordinator?.performUndo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .inkwellRedo)) { _ in
            activeCoordinator?.performRedo()
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
                                // §11.8: only the active tab drives Edit-menu
                                // enablement. Captures appState (app singleton)
                                // + tab.id (value) — never the coordinator/self.
                                coordinator.onUndoStateChange = { canUndo, canRedo in
                                    if appState.activeTabId == tab.id {
                                        appState.canUndo = canUndo
                                        appState.canRedo = canRedo
                                    }
                                }
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
        panel.begin { [appState] response in
            if response == .OK, let url = panel.url {
                appState.openLibrary(pickedURL: url)
            }
        }
        #else
        // PHASE_5A §二: pick any local folder and persist it via a
        // security-scoped bookmark (was: hard-coded to the sandbox Documents).
        FolderPickerPresenter.present { [appState] url in
            appState.openLibrary(pickedURL: url)
        }
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
