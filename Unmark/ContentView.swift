import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var workspace = Workspace()
    @State private var targeted = false
    @State private var confirmClearTemporaryData = false
    @AppStorage("exportFormat") private var exportFormat = "png"
    private let accent = Color(red: 0.39, green: 0.78, blue: 0.64)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if let receipt = workspace.exportReceipt {
                    exportConfirmation(receipt)
                    Divider()
                }
                if let item = workspace.selected {
                    editor(item)
                } else {
                    emptyState
                }
                Divider()
                footer
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard !workspace.busy else { return false }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in workspace.add([url]) } }
                }
            }
            return true
        }
        .overlay { if targeted { RoundedRectangle(cornerRadius: 12).stroke(accent, lineWidth: 3).padding(6).allowsHitTesting(false) } }
        .background(WindowLifecycle(onClose: { workspace.close() }).frame(width: 0, height: 0))
        .sheet(isPresented: $workspace.showTools) { tools }
        .alert("Something needs attention", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("OK") { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
    }

    private func exportConfirmation(_ receipt: ExportReceipt) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.title).font(.callout.weight(.semibold))
                Text(receipt.folder).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).help(receipt.folder)
                ForEach(receipt.notes, id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(receipt.files)
            }
            Button { workspace.exportReceipt = nil } label: {
                Image(systemName: "xmark").foregroundStyle(.secondary)
            }.buttonStyle(.plain).help("Dismiss export confirmation")
                .accessibilityLabel("Dismiss export confirmation")
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(accent.opacity(0.08))
        .accessibilityElement(children: .contain)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.dashed.inset.filled").font(.title2).foregroundStyle(accent)
                Text("Unmark").font(.title2.weight(.semibold))
            }.padding(24)
            HStack {
                Text("YOUR IMAGES").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Text("\(workspace.items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.bottom, 12)
            List(selection: $workspace.selectedID) {
                ForEach(workspace.items) { item in
                    HStack(spacing: 10) {
                        Image(nsImage: item.image).resizable().scaledToFill().frame(width: 42, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.source.lastPathComponent).lineLimit(1).font(.callout.weight(.medium))
                            Text("\(item.mode) · \(item.status)").font(.caption).foregroundStyle(item.result == nil ? Color.secondary : accent)
                        }
                    }.padding(.vertical, 4).tag(item.id)
                }
            }.listStyle(.sidebar)
            Button { workspace.pick() } label: {
                Label("Add images", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(.bordered).disabled(workspace.busy).padding(16)
            Divider()
            Button { workspace.showTools = true } label: {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                    Text("Tools")
                    Spacer()
                    Circle().fill(workspace.report?.ready == true ? accent : Color.secondary).frame(width: 6, height: 6)
                }.foregroundStyle(.secondary).padding(20)
            }.buttonStyle(.plain)
            SettingsLink {
                Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 18)
            }.buttonStyle(.plain)
        }.frame(width: 248).background(Color.black.opacity(0.12))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workspace.selected?.source.lastPathComponent ?? "A cleaner picture.").font(.headline).lineLimit(1)
                Text("Local processing. Your images stay yours.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if workspace.selected != nil {
                Button { workspace.remove() } label: { Image(systemName: "trash") }.help("Remove image from the list").disabled(workspace.busy)
                Button(exportFormat == "original" ? "Export image" : "Export PNG") { workspace.export(all: false) }.disabled(workspace.selected?.result == nil || workspace.busy)
            }
        }.padding(.horizontal, 26).padding(.vertical, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(accent.opacity(0.08)).frame(width: 96, height: 96)
                Image(systemName: "photo.badge.plus").font(.system(size: 36, weight: .light)).foregroundStyle(accent)
            }
            Text("Less distraction. More image.").font(.system(size: 28, weight: .semibold))
            Text("Drop your images here, or choose a few to get started.") .foregroundStyle(.secondary)
            Button("Choose images…") { workspace.pick() }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("PNG, JPG, HEIC, TIFF, WebP and BMP · 10 MB per image · Up to 25 MP").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            HStack(spacing: 24) {
                Label("Small & large presets", systemImage: "sparkle")
                Label("Draw a custom area", systemImage: "rectangle.dashed")
                Label("Batch cleanup", systemImage: "square.stack")
            }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 32)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }

    private func editor(_ item: ImageItem) -> some View {
        VStack(spacing: 18) {
            HStack {
                Picker("Cleanup area", selection: Binding(get: { workspace.selected?.mode ?? "Small" }, set: { workspace.updateMode($0) })) {
                    ForEach(["Small", "Large", "Custom"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).frame(width: 270).disabled(workspace.busy)
                Spacer()
                if item.result != nil {
                    Button("Reset") { workspace.resetEdits() }.disabled(workspace.busy)
                    Toggle("Original", isOn: $workspace.showOriginal).toggleStyle(.switch).controlSize(.small)
                }
            }
            HStack(spacing: 12) {
                Text("⌘ scroll to zoom · Scroll to move").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { workspace.updateZoom(item.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(item.zoom <= 1).help("Zoom out")
                Text("\(Int((item.zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).frame(width: 48)
                    .help("Zoom relative to Fit")
                Button { workspace.updateZoom(item.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(item.zoom >= 8).help("Zoom in")
                Button("Fit") { workspace.updateZoom(1) }.disabled(item.zoom == 1)
            }.buttonStyle(.borderless)
            ImageCanvas(item: item, showOriginal: workspace.showOriginal, enabled: !workspace.busy,
                        onZoom: { workspace.updateZoom($0) }) { workspace.updateRegion($0) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topLeading) {
                    Text(item.result != nil && !workspace.showOriginal ? "CLEANED" : "ORIGINAL")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.3).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule()).padding(14).allowsHitTesting(false)
                }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.mode == "Custom" ? "Draw around the mark" : "\(item.mode) sparkle preset").font(.callout.weight(.medium))
                    Text(item.mode == "Custom" ? "Drag a rectangle. Leave a little room around the mark and image edges." : "The dashed box shows the area that will be filled.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.editCount > 0 ? "\(item.editCount) edits kept. The next cleanup adds to this result." : "Best on simple backgrounds; detailed areas may leave a visible patch.").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button { Task { await workspace.clean(all: false) } } label: {
                    HStack(spacing: 8) {
                        if workspace.busy { ProgressView().controlSize(.small) } else { Image(systemName: "eraser") }
                        Text(workspace.busy ? "Cleaning…" : "Clean image")
                    }.padding(.horizontal, 6).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).disabled(workspace.busy || (item.mode == "Custom" && item.region == nil))
            }
        }.padding(24)
    }

    private var footer: some View {
        HStack {
            Label(workspace.busy ? workspace.activity : "Originals are kept untouched", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if workspace.busy {
                Button(workspace.cancelling ? "Cancelling…" : "Cancel") { workspace.cancelOperation() }
                    .disabled(workspace.cancelling)
            }
            if !workspace.items.isEmpty {
                Button("Clean all (\(workspace.items.count))") { Task { await workspace.clean(all: true) } }.disabled(workspace.busy)
                Button("Export all…") { workspace.export(all: true) }.disabled(workspace.busy || !workspace.items.contains { $0.result != nil })
            }
        }.padding(.horizontal, 24).padding(.vertical, 14)
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your cleanup tools").font(.title2.weight(.semibold))
                    Text("Unmark uses your installed FFmpeg. No Node.js required.").foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button { workspace.showTools = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            Divider()
            toolRow("FFmpeg", path: workspace.report?.ffmpeg)
            toolRow("FFprobe", path: workspace.report?.ffprobe)
            if let report = workspace.report {
                Text("Last tested: \(report.checkedAt.formatted(date: .abbreviated, time: .shortened)). Rechecked automatically when cleaning.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("Optional folder containing FFmpeg and FFprobe", text: $workspace.toolFolder).textFieldStyle(.roundedBorder)
                Button("Browse…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url { workspace.toolFolder = url.path }
                }
            }.disabled(workspace.testing || workspace.busy)
            Text(workspace.report?.message ?? "Test to check both tools and the delogo filter.")
                .font(.callout).foregroundStyle(workspace.report?.ready == true ? accent : Color.secondary).textSelection(.enabled)
            HStack {
                Link("Installation instructions ↗", destination: URL(string: "https://ffmpeg.org/download.html")!)
                Spacer()
                if workspace.testing {
                    ProgressView().controlSize(.small)
                    Button(workspace.cancelling ? "Cancelling…" : "Cancel") { workspace.cancelOperation() }
                        .disabled(workspace.cancelling)
                }
                Button(workspace.testing ? "Testing…" : "Test tools") { Task { await workspace.testTools() } }
                    .buttonStyle(.borderedProminent).disabled(workspace.testing || workspace.busy)
            }
            Divider()
            Button("Clear temporary data…", role: .destructive) {
                confirmClearTemporaryData = true
            }.disabled(workspace.busy || workspace.testing)
            Text(workspace.temporaryDataNotice ?? "Temporary cleanup results are removed when this window closes. Clearing them now discards unexported edits in this window.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Nothing is installed automatically. Common Homebrew locations are checked, or you can choose a folder above.").font(.caption).foregroundStyle(.tertiary)
        }.padding(28).frame(width: 570)
        .confirmationDialog("Clear temporary data?", isPresented: $confirmClearTemporaryData, titleVisibility: .visible) {
            Button("Clear temporary data", role: .destructive) { workspace.clearTemporaryData() }
        } message: {
            Text("This discards unexported edits in this window. Original images and exported files are kept.")
        }
    }

    private func toolRow(_ name: String, path: String?) -> some View {
        HStack {
            Image(systemName: path == nil ? "circle.dashed" : "checkmark.circle.fill").foregroundStyle(path == nil ? Color.secondary : accent)
            Text(name).font(.headline)
            Spacer()
            Text(path ?? "Not tested / not found").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
