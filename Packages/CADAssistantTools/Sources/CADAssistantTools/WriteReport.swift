import CADModel
import Foundation
import SwiftUIAssistant

/// What a write tool tells the model: the edited feature's status, statuses that changed elsewhere, every body's
/// validity and size, and the listing lines that changed.
struct WriteReport {
    var summary: String
    var focus: UUID?
    var notes: [String] = []
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
            lines += changes.map { "  \($0)" }
        }
        if !notes.isEmpty {
            lines.append("Body references renumbered:")
            lines += notes.map { "  \($0)" }
        }
        let bodies = afterResult.parts.flatMap { part in part.bodies.map { Self.describe($0, in: part.name) } }
        lines.append(bodies.isEmpty ? "Bodies: none" : "Bodies:")
        lines += bodies.map { "  \($0)" }
        let diff = Self.diff(
            DocumentListing.lines(before, result: beforeResult), DocumentListing.lines(after, result: afterResult))
        if !diff.isEmpty {
            lines.append("Listing changes:")
            lines += diff.map { "  \($0)" }
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

    static func describe(_ body: BodyResult, in part: String) -> String {
        let name = "\(body.name) (\(part))"
        guard let metrics = body.metrics else { return "\(name): error: \(body.error ?? "no metrics")" }
        var problems: [String] = []
        if !metrics.isValid { problems.append("invalid shape") }
        if !metrics.isClosed { problems.append("not closed") }
        if metrics.solidCount != 1 { problems.append("\(metrics.solidCount) solids") }
        let state = problems.isEmpty ? "valid closed solid" : "problems: \(problems.joined(separator: ", "))"
        let volume = metrics.volume.map { "volume \(Format.number($0)) mm³" } ?? "volume unknown"
        return
            "\(name): \(state), \(volume), bounds \(Format.point(metrics.boundsMin)) to \(Format.point(metrics.boundsMax))"
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
}

extension CADSession {
    /// Applies one tool edit as a single undoable step: validates it, keeps body references pointing at the same
    /// creating features, refuses new expression failures, commits, rebuilds and reports.
    func write(_ change: (inout CADDocument) throws(ToolError) -> WriteFocus) async -> ToolExecutionResult {
        let beforeResult = await currentResult()
        let before = document
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
            summary: focus.summary, focus: focus.feature, notes: notes, before: before,
            beforeResult: beforeResult, after: after, afterResult: afterResult)
        return .success(report.render())
    }
}
