import SwiftUI

@main
struct InkwellApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        #if os(macOS)
        // macOS: Window-based with sidebar
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            InkwellCommands(appState: appState)
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #else
        // iOS: Navigation-based
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        #endif
    }
}
