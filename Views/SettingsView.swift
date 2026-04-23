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
            
            Section("Auto Save") {
                Toggle("Enable auto-save", isOn: $autoSave)
                
                if autoSave {
                    HStack {
                        Text("Save every")
                        Spacer()
                        Slider(value: $autoSaveInterval, in: 1...30, step: 1) {
                            Text("Interval")
                        }
                        .frame(width: 150)
                        Text("\(Int(autoSaveInterval))s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            }
        }
        .padding()
    }
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
                        appState.workingDirectory = url
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
