import SwiftUI

@main
struct UnmarkApp: App {
    init() {
        TemporaryStorage.clearAbandoned()
        _ = MCPAccess.shared
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands { AboutCommands() }
        Settings {
            AppSettingsView()
        }
        Window("About Unmark", id: "about") {
            AboutView().frame(width: 560, height: 520)
        }
        .windowResizability(.contentSize)
    }
}
