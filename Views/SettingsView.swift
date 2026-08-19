import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = "themes"
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ThemeSettingsView()
                .environmentObject(appState)
                .tabItem { Label("Themes", systemImage: "paintbrush") }
                .tag("themes")
            
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem { Label("General", systemImage: "gear") }
                .tag("general")
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - Theme Settings

struct ThemeSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Choose a theme")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: importCustomCSS) {
                    Label("Import CSS", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Theme grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    // Built-in themes
                    ForEach(BuiltInThemes.all) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: appState.currentThemeId == theme.id,
                            onSelect: { appState.applyTheme(id: theme.id) },
                            onDelete: nil
                        )
                    }
                    
                    // Custom themes
                    ForEach(appState.customThemes) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: appState.currentThemeId == theme.id,
                            onSelect: { appState.applyTheme(id: theme.id) },
                            onDelete: { appState.removeCustomTheme(theme) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    private func importCustomCSS() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "css")!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a CSS theme file"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                appState.loadCustomCSS(from: url)
            }
        }
        #endif
    }
}

// MARK: - Theme Card

struct ThemeCard: View {
    let theme: ThemeInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Preview area: simulated editor look
            ZStack {
                // Background
                Rectangle()
                    .fill(theme.bgColor)
                
                // Simulated content lines
                VStack(alignment: .leading, spacing: 6) {
                    // "Heading"
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.textColor)
                        .frame(width: 60, height: 8)
                    
                    // "Paragraph" lines
                    RoundedRectangle(cornerRadius: 1)
                        .fill(theme.textColor.opacity(0.5))
                        .frame(width: 100, height: 5)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(theme.textColor.opacity(0.5))
                        .frame(width: 80, height: 5)
                    
                    // "Accent" element (blockquote bar or link)
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(theme.accentColor)
                            .frame(width: 2, height: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(theme.textColor.opacity(0.35))
                                .frame(width: 70, height: 4)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(theme.textColor.opacity(0.35))
                                .frame(width: 50, height: 4)
                        }
                    }
                    
                    // "Code block"
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.textColor.opacity(0.06))
                        .frame(width: 90, height: 18)
                        .overlay(
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(theme.accentColor.opacity(0.6))
                                    .frame(width: 20, height: 3)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(theme.textColor.opacity(0.3))
                                    .frame(width: 30, height: 3)
                            }
                            .padding(.leading, 6),
                            alignment: .leading
                        )
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Theme name + delete button
            HStack(spacing: 4) {
                Text(theme.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                if !theme.isBuiltIn, isHovering, let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 2)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 17
    @AppStorage("editorLineHeight") private var lineHeight: Double = 1.75
    // NOT wired to any timer yet. Disk writes currently happen on Cmd+S, tab
    // close/rename, and lifecycle flushes (scenePhase / app quit / tab switch).
    // These two prefs — and any values already stored under these keys — are
    // retained for a future timed-autosave implementation; their Settings UI
    // (Toggle + interval Slider) is hidden until that lands.
    @AppStorage("autoSave") private var autoSave: Bool = true
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 5
    
    var body: some View {
        Form {
            Section("Editor") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Slider(value: $fontSize, in: 12...24, step: 1) {
                        Text("Font Size")
                    }
                    .frame(width: 150)
                    Text("\(Int(fontSize))px")
                        .monospacedDigit()
                        .frame(width: 40)
                }
                
                HStack {
                    Text("Line Height")
                    Spacer()
                    Slider(value: $lineHeight, in: 1.2...2.5, step: 0.05) {
                        Text("Line Height")
                    }
                    .frame(width: 150)
                    Text(String(format: "%.2f", lineHeight))
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
        }
        .padding()
    }
}

// MARK: - Undo/Redo command routing (§11.8)

extension Notification.Name {
    static let inkwellUndo = Notification.Name("inkwellUndo")
    static let inkwellRedo = Notification.Name("inkwellRedo")
}

// MARK: - macOS Menu Commands

#if os(macOS)
struct InkwellCommands: Commands {
    @ObservedObject var appState: AppState
    
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") {
                let dir = appState.workingDirectory
                    ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let _ = appState.createNewFile(in: dir)
            }
            .keyboardShortcut("n", modifiers: .command)
            
            Button("Open Folder...") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        appState.openLibrary(pickedURL: url)
                    }
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            
            Button("Open File...") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [UTType(filenameExtension: "md")!]
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        appState.openFile(url)
                    }
                }
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        
        // §11.8: replace the default Undo/Redo so the WKWebView's native
        // undoManager is never invoked (dual-stack is the worst failure mode).
        // These route into the JS self-built stack via NotificationCenter →
        // ContentView → the active editor coordinator.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                NotificationCenter.default.post(name: .inkwellUndo, object: nil)
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!appState.canUndo)

            Button("Redo") {
                NotificationCenter.default.post(name: .inkwellRedo, object: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!appState.canRedo)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                appState.saveCurrentDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appState.currentDocument == nil)
        }
        
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                appState.isSidebarVisible.toggle()
            }
            .keyboardShortcut("\\", modifiers: .command)
        }
    }
}
#endif
