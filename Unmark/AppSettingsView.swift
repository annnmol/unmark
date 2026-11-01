import SwiftUI

struct AppSettingsView: View {
    @AppStorage("exportFormat") private var exportFormat = "png"

    var body: some View {
        TabView {
            exportSettings.tabItem { Label("General", systemImage: "gearshape") }
            MCPSettingsView().tabItem { Label("AI access", systemImage: "sparkles") }
            AboutView().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 570)
        .navigationTitle("Unmark Settings")
    }

    private var exportSettings: some View {
        Form {
            Section("Export") {
                Picker("Image format", selection: $exportFormat) {
                    Text("PNG (default)").tag("png")
                    Text("Same as input").tag("original")
                }
                Text("PNG saves without additional lossy compression. Same as input preserves the file format where macOS supports writing it; otherwise, Unmark saves PNG and tells you.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("JPG/JPEG and HEIC exports use high quality compression. Edits remain PNG internally so repeated cleanups avoid repeated JPEG compression.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Supported images") {
                Text("10 MB per image · Up to 25 megapixels")
                Text("PNG, JPG/JPEG, TIFF, BMP, HEIC and WebP")
                Text("Still images only. Same-format export depends on this Mac’s available encoders. Preserving the format does not preserve all original metadata.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
