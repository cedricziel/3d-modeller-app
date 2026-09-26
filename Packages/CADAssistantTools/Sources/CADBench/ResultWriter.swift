import Foundation

public struct Redactor: Sendable {
    private let secrets: [String]

    public init(secrets: [String]) {
        self.secrets = secrets.filter { $0.count >= 8 }
    }

    public func callAsFunction(_ text: String) -> String {
        secrets.reduce(text) { $0.replacingOccurrences(of: $1, with: "[redacted]") }
    }
}

public enum BenchClock {
    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}

/// Writes each run's document, listing, transcript, grade and renders, and the summary, with secrets redacted from
/// the text files.
public struct ResultWriter {
    public let directory: URL
    public let redactor: Redactor

    public init(directory: URL, redactor: Redactor) {
        self.directory = directory
        self.redactor = redactor
    }

    /// The folder of one run's files.
    public func folder(task: String, attempt: Int) -> URL {
        directory.appending(path: task).appending(path: "run-\(attempt)")
    }

    public func write(_ record: RunRecord) throws {
        let folder = folder(task: record.task, attempt: record.attempt)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(record.document.jsonData(), to: folder.appending(path: "document.cadmodel"))
        try write(Data(record.listing.utf8), to: folder.appending(path: "listing.txt"))
        try write(Self.json(record.transcript), to: folder.appending(path: "transcript.json"))
        try write(Self.json(RunSummary(record)), to: folder.appending(path: "run.json"))
        if let step = record.step {
            try write(step, to: folder.appending(path: "final.step"))
        }
        for render in record.renders {
            try render.png.write(to: folder.appending(path: "view-\(render.view.rawValue).png"), options: .atomic)
        }
    }

    public func write(_ summary: BenchSummary) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(Self.json(summary), to: directory.appending(path: "summary.json"))
        try write(Data(summary.markdown.utf8), to: directory.appending(path: "summary.md"))
    }

    private func write(_ data: Data, to url: URL) throws {
        try Data(redactor(String(decoding: data, as: UTF8.self)).utf8).write(to: url, options: .atomic)
    }

    private static func json(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
