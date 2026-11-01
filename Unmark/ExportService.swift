import Foundation

nonisolated struct ExportJob: Sendable {
    let source: URL
    let cleaned: URL
    let destination: URL
    let preference: String
    let replaceExisting: Bool
}

nonisolated struct ExportOutcome: Sendable {
    var files: [URL] = []
    var notes: Set<String> = []
    var failure: String?
    var cancelled = false
}

actor ExportService {
    static let shared = ExportService()
    func save(_ jobs: [ExportJob], cancellation: OperationCancellation) -> ExportOutcome {
        var outcome = ExportOutcome()
        do {
            for job in jobs {
                try cancellation.check()
                let format = ImageFormats.output(original: job.source, preference: job.preference)
                let data = try ImageFormats.encodedData(from: job.cleaned, format: format)
                try cancellation.check()
                try data.write(to: job.destination, options: job.replaceExisting ? .atomic : .withoutOverwriting)
                outcome.files.append(job.destination)
                if let reason = format.fallbackReason { outcome.notes.insert(reason) }
            }
        } catch is CancellationError {
            outcome.cancelled = true
        } catch {
            outcome.failure = error.localizedDescription
        }
        return outcome
    }
}
