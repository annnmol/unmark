import Foundation
import CoreGraphics

struct ToolReport: Sendable, Codable {
    var checkedAt = Date()
    var ffmpeg: String?
    var ffprobe: String?
    var message: String
    var ready: Bool { ffmpeg != nil && ffprobe != nil && message == "Ready to clean" }
}

struct CleanupFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Processes and their output are owned by this actor, never the UI thread.
actor CleanupEngine {
    static let shared = CleanupEngine()

    private func executable(_ name: String, folder: String) -> String? {
        let directories = [folder, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        return directories.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func removeWorkspace(_ directory: URL) { try? FileManager.default.removeItem(at: directory) }

    func check(folder: String, cancellation: OperationCancellation = OperationCancellation()) -> ToolReport {
        let ffmpeg = executable("ffmpeg", folder: folder)
        let ffprobe = executable("ffprobe", folder: folder)
        guard let ffmpeg, let ffprobe else {
            return ToolReport(ffmpeg: ffmpeg, ffprobe: ffprobe, message: "Install FFmpeg (including FFprobe), or choose its bin folder.")
        }
        do {
            _ = try ProcessRunner.run(ffmpeg, ["-version"], timeout: 10, cancellation: cancellation)
            _ = try ProcessRunner.run(ffprobe, ["-version"], timeout: 10, cancellation: cancellation)
            let filters = try ProcessRunner.run(ffmpeg, ["-hide_banner", "-filters"], timeout: 10, cancellation: cancellation)
            guard filters.contains(" delogo ") else {
                throw CleanupFailure(message: "This FFmpeg build does not include the delogo filter.")
            }
            return ToolReport(ffmpeg: ffmpeg, ffprobe: ffprobe, message: "Ready to clean")
        } catch {
            return ToolReport(ffmpeg: ffmpeg, ffprobe: ffprobe, message: error.localizedDescription)
        }
    }

    func clean(input: URL, mode: String, region: CGRect?, folder: String, workspace: URL? = nil, cancellation: OperationCancellation = OperationCancellation()) throws -> URL {
        guard let ffmpeg = executable("ffmpeg", folder: folder), let ffprobe = executable("ffprobe", folder: folder) else {
            throw CleanupFailure(message: "FFmpeg or FFprobe is missing. Open Tools and test your installation.")
        }
        // Normalize orientation and format first so the displayed image and pixel coordinates agree.
        try cancellation.check()
        let temp = (workspace ?? TemporaryStorage.base).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let normalized = temp.appendingPathComponent("source.png")
        let output = temp.appendingPathComponent("cleaned.png")
        let filtered = temp.appendingPathComponent("filtered.png")
        do {
            try ImageFormats.normalize(input, to: normalized)
            try cancellation.check()
            let info = try ProcessRunner.run(ffprobe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", normalized.path], timeout: 10, cancellation: cancellation)
            let dimensions = info.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").compactMap { Int($0) }
            guard dimensions.count == 2 else { throw CleanupFailure(message: "Could not read image dimensions.") }
            let w = dimensions[0], h = dimensions[1]
            let k = Double(min(w, h)) / 1536
            let box: CGRect
            if mode == "Custom" {
                guard let region else { throw CleanupFailure(message: "Draw a rectangle on the image first.") }
                box = CGRect(x: region.minX * Double(w), y: region.minY * Double(h), width: region.width * Double(w), height: region.height * Double(h))
            } else if mode == "Large" {
                box = CGRect(x: Double(w) - 256 * k, y: Double(h) - 257 * k, width: 124 * k, height: 124 * k)
            } else {
                box = CGRect(x: Double(w) - 146 * k, y: Double(h) - 146 * k, width: 66 * k, height: 66 * k)
            }
            // delogo needs surrounding pixels on all four sides.
            let x = max(1, Int(box.minX.rounded())), y = max(1, Int(box.minY.rounded()))
            let bw = min(Int(box.width.rounded()), w - x - 1), bh = min(Int(box.height.rounded()), h - y - 1)
            guard bw >= 3, bh >= 3 else { throw CleanupFailure(message: "Choose a larger area with a little space from the image edges.") }
            _ = try ProcessRunner.run(ffmpeg, ["-v", "error", "-nostdin", "-i", normalized.path, "-vf", "delogo=x=\(x):y=\(y):w=\(bw):h=\(bh)", "-frames:v", "1", filtered.path], cancellation: cancellation)
            try cancellation.check()
            try ImageFormats.composite(original: normalized, filtered: filtered,
                                       box: CGRect(x: x, y: y, width: bw, height: bh), output: output)
            try cancellation.check()
            try? FileManager.default.removeItem(at: filtered)
            try? FileManager.default.removeItem(at: normalized)
            return output
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
