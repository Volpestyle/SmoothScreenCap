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
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    appState.undo()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!appState.canUndo)

                Button("Redo") {
                    appState.redo()
                }
                .keyboardShortcut("Z", modifiers: [.command, .shift])
                .disabled(!appState.canRedo)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
