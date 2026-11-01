import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportReceipt {
    let files: [URL]
    var notes: [String] = []
    var title: String { files.count == 1 ? "Image saved" : "\(files.count) images saved" }
    var folder: String { files.first?.deletingLastPathComponent().path ?? "" }
}

struct ImageItem: Identifiable {
    let id = UUID()
    let source: URL
    let image: NSImage
    var mode = "Small"
    var zoom: CGFloat = 1
    var editCount = 0
    var region: CGRect?
    var result: URL?
    var resultImage: NSImage?
    var status = "Ready"
}

@MainActor @Observable
final class Workspace {
    var items: [ImageItem] = []
    var selectedID: UUID? {
        didSet { if oldValue != selectedID { showOriginal = false } }
    }
    var busy = false
    var testing = false
    var cancelling = false
    var activity = ""
    private var operation: OperationCancellation?
    private let storage = TemporaryStorage()
    private var closed = false
    var temporaryDataNotice: String?
    var report: ToolReport? {
        didSet {
            if let report, let data = try? JSONEncoder().encode(report) {
                defaults.set(data, forKey: "toolReport")
            } else {
                defaults.removeObject(forKey: "toolReport")
            }
        }
    }
    var error: String?
    var exportReceipt: ExportReceipt?
    var showTools = false
    var showOriginal = false
    var toolFolder: String {
        didSet { defaults.set(toolFolder, forKey: "toolFolder"); report = nil }
    }
    var selected: ImageItem? { items.first { $0.id == selectedID } }

    private let defaults: UserDefaults
    var exportPreference: String { defaults.string(forKey: "exportFormat") ?? "png" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        toolFolder = defaults.string(forKey: "toolFolder") ?? ""
        if let data = defaults.data(forKey: "toolReport") {
            report = try? JSONDecoder().decode(ToolReport.self, from: data)
        }
    }
    func add(_ urls: [URL]) {
        guard !busy else { return }
        var rejected: [String] = []
        for url in urls {
            guard url.isFileURL else { continue }
            do { try ImageFormats.validateImport(url) }
            catch { rejected.append("\(url.lastPathComponent): \(error.localizedDescription)"); continue }
            guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
                rejected.append(url.lastPathComponent); continue
            }
            if let existing = items.first(where: { $0.source == url }) { selectedID = existing.id; continue }
            let item = ImageItem(source: url, image: image)
            items.append(item)
            selectedID = item.id
        }
        if !rejected.isEmpty { error = "Could not open: " + rejected.joined(separator: ", ") }
    }
    func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .webP, .bmp]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func updateMode(_ mode: String) {
        guard let i = items.firstIndex(where: { $0.id == selectedID }), !busy else { return }
        items[i].mode = mode
        showOriginal = false
    }
    func updateRegion(_ rect: CGRect) {
        guard let i = items.firstIndex(where: { $0.id == selectedID }), !busy else { return }
        items[i].region = rect
        showOriginal = false
    }
    func updateZoom(_ zoom: CGFloat) {
        guard let i = items.firstIndex(where: { $0.id == selectedID }) else { return }
        items[i].zoom = min(8, max(1, zoom))
    }
    func resetEdits() {
        guard !busy, let i = items.firstIndex(where: { $0.id == selectedID }) else { return }
        invalidate(i)
        items[i].region = nil
    }
    private func invalidate(_ i: Int) {
        if let result = items[i].result { try? FileManager.default.removeItem(at: result.deletingLastPathComponent()) }
        items[i].result = nil; items[i].resultImage = nil; items[i].status = "Ready"
        items[i].editCount = 0
        showOriginal = false
    }
    func remove() {
        guard !busy, let i = items.firstIndex(where: { $0.id == selectedID }) else { return }
        invalidate(i)
        items.remove(at: i)
        selectedID = items.first?.id
    }
    func cancelOperation() {
        guard busy || testing else { return }
        cancelling = true
        operation?.cancel()
    }

    func clearTemporaryData() {
        guard !busy, !testing else { return }
        for i in items.indices { invalidate(i); items[i].region = nil }
        storage.clear()
        temporaryDataNotice = "Temporary data cleared. Original images and exported files are unchanged."
    }

    func close() {
        guard !closed else { return }
        closed = true
        operation?.cancel()
        storage.clear()
        let directory = storage.directory
        // The actor removes any directory created by an in-flight cleanup after
        // cancellation was requested. Other windows use their own directories.
        Task { await CleanupEngine.shared.removeWorkspace(directory) }
    }

    func testTools() async {
        guard !busy, !testing, !closed else { return }
        let token = OperationCancellation()
        operation = token
        testing = true
        defer { testing = false; cancelling = false; operation = nil }
        let checked = await CleanupEngine.shared.check(folder: toolFolder, cancellation: token)
        if !token.isCancelled && !closed { report = checked }
    }

    func clean(all: Bool) async {
        guard !busy, !testing, !closed else { return }
        let targets = all ? items.map(\.id) : [selectedID].compactMap { $0 }
        guard !targets.isEmpty else { return }
        let token = OperationCancellation()
        operation = token
        busy = true
        activity = "Checking tools…"
        defer { busy = false; cancelling = false; operation = nil; activity = "" }
        let checked = await CleanupEngine.shared.check(folder: toolFolder, cancellation: token)
        guard !token.isCancelled, !closed else { return }
        report = checked
        guard checked.ready else { showTools = true; return }
        for (position, id) in targets.enumerated() {
            if token.isCancelled || closed { break }
            guard let i = items.firstIndex(where: { $0.id == id }) else { continue }
            let item = items[i]
            activity = "Cleaning \(position + 1) of \(targets.count)…"
            items[i].status = "Cleaning…"
            do {
                // Check externally modified input files again before decoding.
                if item.result == nil { try ImageFormats.validateImport(item.source) }
                let result = try await CleanupEngine.shared.clean(input: item.result ?? item.source, mode: item.mode,
                    region: item.region, folder: toolFolder, workspace: storage.directory, cancellation: token)
                guard !token.isCancelled, !closed else {
                    try? FileManager.default.removeItem(at: result.deletingLastPathComponent())
                    items[i].status = "Cancelled"
                    break
                }
                if let old = items[i].result { try? FileManager.default.removeItem(at: old.deletingLastPathComponent()) }
                items[i].result = result
                items[i].resultImage = NSImage(contentsOf: result)
                items[i].editCount += 1
                items[i].status = "Cleaned · \(items[i].editCount) edits"
                showOriginal = false
            } catch {
                if token.isCancelled || closed || error is CancellationError {
                    items[i].status = "Cancelled"
                    break
                }
                items[i].status = "Needs attention"
                self.error = "\(item.source.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func export(all: Bool) {
        guard !busy, !testing, !closed else { return }
        let targets = all ? items.filter { $0.result != nil } : [selected].compactMap { $0 }.filter { $0.result != nil }
        guard !targets.isEmpty else { return }
        exportReceipt = nil
        let preference = exportPreference
        var jobs: [ExportJob] = []
        if !all, let item = targets.first, let result = item.result {
            let format = ImageFormats.output(original: item.source, preference: preference)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [format.type]
            panel.nameFieldStringValue = item.source.deletingPathExtension().lastPathComponent + "-unmarked." + format.fileExtension
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            let resolved = destination.resolvingSymlinksInPath().standardizedFileURL
            guard !items.contains(where: { $0.source.resolvingSymlinksInPath().standardizedFileURL == resolved }) else {
                error = "Choose a different filename to preserve your original images."
                return
            }
            jobs.append(ExportJob(source: item.source, cleaned: result, destination: destination,
                                  preference: preference, replaceExisting: true))
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.prompt = "Export here"
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            var reserved = Set<URL>()
            for item in targets {
                guard let result = item.result else { continue }
                let format = ImageFormats.output(original: item.source, preference: preference)
                let name = item.source.deletingPathExtension().lastPathComponent + "-unmarked"
                var destination = directory.appendingPathComponent(name + "." + format.fileExtension)
                var suffix = 2
                while FileManager.default.fileExists(atPath: destination.path) || reserved.contains(destination) {
                    destination = directory.appendingPathComponent("\(name)-\(suffix)." + format.fileExtension)
                    suffix += 1
                }
                reserved.insert(destination)
                jobs.append(ExportJob(source: item.source, cleaned: result, destination: destination,
                                      preference: preference, replaceExisting: false))
            }
        }
        let token = OperationCancellation()
        operation = token
        busy = true
        activity = "Exporting \(jobs.count) image(s)…"
        Task {
            defer { busy = false; cancelling = false; operation = nil; activity = "" }
            let outcome = await ExportService.shared.save(jobs, cancellation: token)
            guard !closed else { return }
            if let failure = outcome.failure {
                error = "Export stopped after saving \(outcome.files.count) of \(jobs.count) images. \(failure)"
            } else if outcome.cancelled {
                error = "Export cancelled. \(outcome.files.count) of \(jobs.count) images were saved."
            } else if !outcome.files.isEmpty {
                exportReceipt = ExportReceipt(files: outcome.files, notes: outcome.notes.sorted())
            }
        }
    }
}
