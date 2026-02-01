import SwiftUI

@main
struct SmoothScreenCapApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1400, height: 900)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
