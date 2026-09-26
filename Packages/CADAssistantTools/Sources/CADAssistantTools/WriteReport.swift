import CADModel
import Foundation
import SwiftUIAssistant

/// What a write tool tells the model: the edited feature's status, statuses that changed elsewhere, every body's
/// validity and size, and the listing lines that changed.
struct WriteReport {
    var summary: String
    var focus: UUID?
    var notes: [String] = []
    var referenceNotes: [String] = []
    var before: CADDocument
    var beforeResult: RebuildResult?
    var after: CADDocument
    var afterResult: RebuildResult?

    func render() -> String {
        var lines = [summary]
        guard let afterResult else {
            lines.append("The rebuild did not finish; call get_listing to see the statuses.")
            return lines.joined(separator: "\n")
        }
        if let focus, let feature = afterResult.feature(id: focus) {
            lines.append("\(feature.name): \(feature.status)")
        }
        let changes = statusChanges(afterResult)
        if !changes.isEmpty {
            lines.append("Status changes elsewhere:")
            lines += changes.prefix(Self.diffLimit).map { "  \($0)" }
            if changes.count > Self.diffLimit {
                lines.append("  … \(changes.count - Self.diffLimit) more status changes; call get_listing")
            }
        }
        if !notes.isEmpty {
            lines.append("Body references renumbered:")
            lines += notes.map { "  \($0)" }
        }
        if !referenceNotes.isEmpty {
            lines.append("Geometry references updated:")
            lines += referenceNotes.map { "  \($0)" }
        }
        lines += bodyLines(afterResult)
        let diff = Self.diff(
            DocumentListing.lines(before, result: beforeResult), DocumentListing.lines(after, result: afterResult))
        if !diff.isEmpty {
            lines.append("Listing changes:")
            lines += diff.prefix(Self.diffLimit).map { "  \($0)" }
            if diff.count > Self.diffLimit {
                lines.append("  … \(diff.count - Self.diffLimit) more changed lines; call get_listing")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func statusChanges(_ afterResult: RebuildResult) -> [String] {
        guard let beforeResult else { return [] }
        return afterResult.parts.flatMap(\.features).compactMap { feature in
            guard feature.id != focus, let old = beforeResult.feature(id: feature.id), old.status != feature.status
            else { return nil }
            return "\(feature.name): \(old.status) → \(feature.status)"
        }
    }

    static let diffLimit = 30

    /// New, changed and faulty bodies in full; bodies that are valid and unchanged by name only.
    private func bodyLines(_ afterResult: RebuildResult) -> [String] {
        let old = Dictionary(
            (beforeResult?.parts ?? []).flatMap { part in part.bodies.map { ("\($0.name) (\(part.name))", $0) } },
            uniquingKeysWith: { first, _ in first })
        var changed: [String] = []
        var unchanged: [String] = []
        var seen = Set<String>()
        for part in afterResult.parts {
            for body in part.bodies {
                let key = "\(body.name) (\(part.name))"
                seen.insert(key)
                let line = Self.describe(body, in: part.name)
                if Self.isSound(body), let previous = old[key], Self.describe(previous, in: part.name) == line {
                    unchanged.append(key)
                } else {
                    changed.append(line)
                }
            }
        }
        let removed = (beforeResult?.parts ?? []).flatMap { part in part.bodies.map { "\($0.name) (\(part.name))" } }
            .filter { !seen.contains($0) }
        var lines: [String] = []
        if changed.isEmpty && unchanged.isEmpty { lines.append("Bodies: none") }
        if !changed.isEmpty { lines.append("Bodies:") }
        lines += changed.map { "  \($0)" }
        if !unchanged.isEmpty { lines.append("Unchanged bodies: \(unchanged.joined(separator: ", "))") }
        if !removed.isEmpty { lines.append("Removed bodies: \(removed.joined(separator: ", "))") }
        return lines
    }

    static func isSound(_ body: BodyResult) -> Bool {
        guard let metrics = body.metrics else { return false }
        return metrics.isValid && metrics.isClosed && metrics.solidCount == 1
    }

    static func describe(_ body: BodyResult, in part: String) -> String {
        let name = "\(body.name) (\(part))"
        guard let metrics = body.metrics else { return "\(name): error: \(body.error ?? "no metrics")" }
        var problems: [String] = []
        if !metrics.isValid { problems.append("invalid shape") }
        if !metrics.isClosed { problems.append("not closed") }
        if metrics.solidCount != 1 { problems.append("\(metrics.solidCount) solids") }
        let state = problems.isEmpty ? "valid closed solid" : "problems: \(problems.joined(separator: ", "))"
        let counts = "\(metrics.faceCount) faces" + (body.topology.map { ", \($0.edges.count) edges" } ?? "")
        let volume = metrics.volume.map { "volume \(Format.number($0)) mm³" } ?? "volume unknown"
        return
            "\(name): \(state), \(counts), \(volume), bounds \(Format.point(metrics.boundsMin)) to \(Format.point(metrics.boundsMax))"
    }

    /// Lines only in `old` as "- …", then lines only in `new` as "+ …", each in its listing's order.
    static func diff(_ old: [String], _ new: [String]) -> [String] {
        func unmatched(_ lines: [String], against other: [String]) -> [String] {
            var available = Dictionary(other.map { ($0, 1) }, uniquingKeysWith: +)
            return lines.filter { line in
                guard let count = available[line], count > 0 else { return true }
                available[line] = count - 1
                return false
            }
        }
        let trim = { (line: String) in line.trimmingCharacters(in: .whitespaces) }
        return unmatched(old, against: new).map { "- " + trim($0) }
            + unmatched(new, against: old).map { "+ " + trim($0) }
    }
}

struct WriteFocus {
    var actionName: String
    var summary: String
    var feature: UUID?
    var referenceNotes: [String] = []
}

extension CADSession {
    /// Applies one tool edit as a single undoable step: validates it, keeps body references pointing at the same
    /// creating features, refuses new expression failures, commits, rebuilds and reports.
    func write(_ change: (inout CADDocument) throws(ToolError) -> WriteFocus) async -> ToolExecutionResult {
        var beforeResult = await currentResult()
        if !isResultCurrent { beforeResult = await currentResult() }
        let before = document
        if !isResultCurrent { beforeResult = nil }
        var after = before
        let focus: WriteFocus
        let notes: [String]
        do throws(ToolError) {
            focus = try change(&after)
            notes = try BodyReferenceRepair.apply(from: before, to: &after)
            try ExpressionAudit.check(before: before, after: after)
        } catch {
            return .failure(error.description)
        }
        guard after != before else { return .success("\(focus.summary). Nothing changed.") }
        let afterResult = await apply(after, actionName: focus.actionName)
        let report = WriteReport(
            summary: focus.summary, focus: focus.feature, notes: notes, referenceNotes: focus.referenceNotes,
            before: before,
            beforeResult: beforeResult, after: after, afterResult: afterResult)
        return .success(report.render())
    }
}
