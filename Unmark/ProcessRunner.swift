import Foundation
import Darwin

nonisolated final class OperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() {
        let active = lock.withLock { cancelled = true; return process }
        if let active, active.isRunning { active.terminate() }
    }
    func track(_ active: Process) {
        let stopped = lock.withLock { process = active; return cancelled }
        if stopped && active.isRunning { active.terminate() }
    }
    func untrack() { lock.withLock { process = nil } }
    func check() throws { if isCancelled { throw CancellationError() } }
}

nonisolated enum ProcessRunner {
    /// Uses a disk log rather than a pipe, so inherited output handles cannot keep
    /// this reader blocked after the process exits. Log reads are bounded to 256 KB.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 60,
                    cancellation: OperationCancellation = OperationCancellation()) throws -> String {
        try cancellation.check()
        let directory = TemporaryStorage.base.appendingPathComponent("\(getpid())-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("output.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        cancellation.track(process)
        defer { cancellation.untrack() }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var stoppedAt: TimeInterval?
        var timedOut = false
        while process.isRunning {
            let now = ProcessInfo.processInfo.systemUptime
            if stoppedAt == nil && (cancellation.isCancelled || now >= deadline) {
                timedOut = now >= deadline && !cancellation.isCancelled
                stoppedAt = now
                process.terminate()
            }
            if let stoppedAt, now - stoppedAt > 0.3, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
        process.waitUntilExit()
        try cancellation.check()
        if timedOut { throw CleanupFailure(message: "The tool exceeded its \(Int(timeout))-second time limit. You can retry the operation.") }
        let reader = try FileHandle(forReadingFrom: log)
        defer { try? reader.close() }
        let length = try reader.seekToEnd()
        try reader.seek(toOffset: length > 262_144 ? length - 262_144 : 0)
        let output = String(decoding: try reader.readToEnd() ?? Data(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CleanupFailure(message: output.isEmpty ? "The tool exited with status \(process.terminationStatus)." : String(output.suffix(2400)))
        }
        return output
    }
}
