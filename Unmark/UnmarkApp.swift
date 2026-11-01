import SwiftUI

@main
struct UnmarkApp: App {
    init() { TemporaryStorage.clearAbandoned() }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        Settings {
            AppSettingsView()
        }
    }
}
