import SwiftUI

@main
struct InkwellApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        #if os(macOS)
        // macOS: Window-based with sidebar
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 500)
                // Source-of-truth flush on scenePhase change. .inactive covers app
                // deactivation (switching to another app); .background is the last
                // chance before suspension. App termination is handled separately
                // (AppState's willTerminate observer on macOS).
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background || phase == .inactive {
                        appState.flushDirtyDocuments()
                    }
                }
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
                // iOS: .background is the last callback before the app may be
                // killed from the background, so flushing dirty tabs here is the
                // safety net (kill-from-background gives no further callback).
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background || phase == .inactive {
                        appState.flushDirtyDocuments()
                    }
                }
        }
        #endif
    }
}
