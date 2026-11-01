import Foundation
import Darwin

nonisolated final class TemporaryStorage: @unchecked Sendable {
    static let base = FileManager.default.temporaryDirectory.appendingPathComponent("Unmark-Workspaces", isDirectory: true)
    let directory = TemporaryStorage.base.appendingPathComponent("\(getpid())-\(UUID().uuidString)", isDirectory: true)

    func clear() { try? FileManager.default.removeItem(at: directory) }
    deinit { clear() }

    /// Runs on startup. Never touches a live process's workspace or unrelated files.
    static func clearAbandoned() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard let prefix = folder.lastPathComponent.split(separator: "-").first,
                  let pid = Int32(prefix), pid > 0 else { continue }
            if kill(pid, 0) == -1 && errno == ESRCH { try? FileManager.default.removeItem(at: folder) }
        }
    }
}
