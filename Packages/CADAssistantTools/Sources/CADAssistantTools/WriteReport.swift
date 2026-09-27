import CADModel
import Foundation
import SwiftUIAssistant

/// What a write tool tells the model: the edited feature's status, statuses that changed elsewhere, every body's
/// validity and size, and the listing lines that changed.
struct WriteReport {
    var summary: String
    var focus: UUID?
    var instanceFocus: UUID?
    var jointFocus: UUID?
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
        if let instanceFocus, let instance = afterResult.assembly?.instance(id: instanceFocus) {
            lines.append("\(instance.name): \(instance.status)")
        }
        if let jointFocus, let joint = afterResult.assembly?.joint(id: jointFocus) {
            let motion = after.joints.first { $0.id == jointFocus }.flatMap { JointMotionText.describe($0, joint) }
            lines.append("\(joint.name): \(joint.status)" + (motion.map { ", \($0)" } ?? ""))
        }
        let changes = statusChanges(afterResult)
        if !changes.isEmpty {
            lines.append("Status changes elsewhere:")
            lines += Self.capped(changes, "status changes", then: "call get_listing")
        }
        if !notes.isEmpty {
            lines.append("Body references renumbered:")
            lines += Self.capped(notes, "renumbered references")
        }
        if !referenceNotes.isEmpty {
            lines.append("Geometry references updated:")
            lines += Self.capped(referenceNotes, "updated references")
        }
        lines += bodyLines(afterResult)
        lines += instanceLines(afterResult)
        lines += jointLines(afterResult)
        let parameters = Self.parameterChanges(before.parameters, after.parameters)
        if !parameters.isEmpty {
            lines.append("Parameters:")
            lines += Self.capped(parameters, "changed parameters", then: "call get_listing")
        }
        let statusless = reportedStatuses(afterResult)
        let diff = Self.diff(
            DocumentListing.modelLines(before, result: beforeResult, statusless: statusless),
            DocumentListing.modelLines(after, result: afterResult, statusless: statusless))
        if !diff.isEmpty {
            lines.append("Listing changes:")
            lines += Self.capped(diff, "changed lines", then: "call get_listing")
        }
        return lines.joined(separator: "\n")
    }

    /// The first `diffLimit` entries indented, then how many were left out.
    static func capped(_ entries: [String], _ what: String, then hint: String? = nil) -> [String] {
        var lines = entries.prefix(diffLimit).map { "  \($0)" }
        if entries.count > diffLimit {
            lines.append("  … \(entries.count - diffLimit) more \(what)" + (hint.map { "; \($0)" } ?? ""))
        }
        return lines
    }

    static let nameLimit = 10

    /// Names separated by commas, the first `nameLimit` of them and a count of the rest.
    static func names(_ names: [String]) -> String {
        let shown = names.prefix(nameLimit).joined(separator: ", ")
        return names.count > nameLimit ? "\(shown) and \(names.count - nameLimit) more" : shown
    }

    /// Features, instances and joints kept by the edit, whose status the focus line or the status changes already
    /// report, so their listing lines change only when something besides the status did.
    private func reportedStatuses(_ afterResult: RebuildResult) -> Set<UUID> {
        guard let beforeResult else { return [] }
        let features = afterResult.parts.flatMap(\.features).map(\.id).filter { beforeResult.feature(id: $0) != nil }
        let instances = (afterResult.assembly?.instances ?? []).map(\.id).filter {
            beforeResult.assembly?.instance(id: $0) != nil
        }
        let joints = (afterResult.assembly?.joints ?? []).map(\.id).filter {
            beforeResult.assembly?.joint(id: $0) != nil
        }
        return Set(features + instances + joints)
    }

    private func statusChanges(_ afterResult: RebuildResult) -> [String] {
        guard let beforeResult else { return [] }
        let features = afterResult.parts.flatMap(\.features).compactMap { feature -> String? in
            guard feature.id != focus, let old = beforeResult.feature(id: feature.id), old.status != feature.status
            else { return nil }
            return "\(feature.name): \(old.status) → \(feature.status)"
        }
        let instances = (afterResult.assembly?.instances ?? []).compactMap { instance -> String? in
            guard instance.id != instanceFocus, let old = beforeResult.assembly?.instance(id: instance.id),
                old.status != instance.status
            else { return nil }
            return "\(instance.name): \(old.status) → \(instance.status)"
        }
        let joints = (afterResult.assembly?.joints ?? []).compactMap { joint -> String? in
            guard joint.id != jointFocus, let old = beforeResult.assembly?.joint(id: joint.id),
                old.status != joint.status
            else { return nil }
            return "\(joint.name): \(old.status) → \(joint.status)"
        }
        return features + instances + joints
    }

    /// Joints that do not hold, and the instances whose solved position changed.
    private func jointLines(_ afterResult: RebuildResult) -> [String] {
        var lines: [String] = []
        let faulty = (afterResult.assembly?.joints ?? []).filter { !$0.status.holds && $0.id != jointFocus }
        if !faulty.isEmpty {
            lines.append("Joints:")
            lines += Self.capped(
                faulty.map { "\($0.name): \($0.status)" }, "joints that do not hold", then: "call get_listing")
        }
        let moved = (afterResult.assembly?.instances ?? []).compactMap { instance -> String? in
            guard let old = beforeResult?.assembly?.instance(id: instance.id),
                old.movedByJoints || instance.movedByJoints,
                let from = old.transform, let to = instance.transform
            else { return nil }
            let (before, after) = (Self.pose(from), Self.pose(to))
            return before == after ? nil : "\(instance.name) \(before) → \(after)"
        }
        if !moved.isEmpty {
            let shown = moved.prefix(Self.nameLimit).joined(separator: "; ")
            let rest = moved.count > Self.nameLimit ? "; and \(moved.count - Self.nameLimit) more" : ""
            lines.append("Moved by joints: \(shown)\(rest)")
        }
        return lines
    }

    /// Where a transform puts the part's origin, and its turn when it has one.
    static func pose(_ transform: RigidTransform) -> String {
        let resolved = transform.resolvedPlacement
        let position = Format.point(resolved.translation)
        guard Format.number(resolved.rotationDegrees) != "0" else { return position }
        return
            "\(position) rotated \(Format.number(resolved.rotationDegrees))° about \(Format.point(resolved.rotationAxis))"
    }

    /// Changed or faulty instances in full with their bounds; the others by name.
    private func instanceLines(_ afterResult: RebuildResult) -> [String] {
        let oldInstances = beforeResult?.assembly?.instances ?? []
        let old = Dictionary(
            oldInstances.map { ($0.id, Self.describe($0, in: before)) }, uniquingKeysWith: { first, _ in first })
        var changed: [String] = []
        var unchanged: [String] = []
        let current = afterResult.assembly?.instances ?? []
        for instance in current {
            let line = Self.describe(instance, in: after)
            let definitionKept = Self.shape(of: instance.id, in: before) == Self.shape(of: instance.id, in: after)
            if instance.status == .ok, definitionKept, old[instance.id] == line {
                unchanged.append(instance.name)
            } else {
                changed.append(line)
            }
        }
        let currentIDs = Set(current.map(\.id))
        let removed = oldInstances.filter { !currentIDs.contains($0.id) }.map(\.name)
        var lines: [String] = []
        if !changed.isEmpty { lines.append("Instances:") }
        lines += Self.capped(changed, "changed instances", then: "call get_listing")
        if !unchanged.isEmpty { lines.append("Unchanged instances: \(Self.names(unchanged))") }
        if !removed.isEmpty { lines.append("Removed instances: \(Self.names(removed))") }
        return lines
    }

    /// The instance without its appearance, which the listing changes already report.
    private static func shape(of id: UUID, in document: CADDocument) -> Instance? {
        var instance = document.instances.first { $0.id == id }
        instance?.appearance = nil
        return instance
    }

    static func describe(_ instance: InstanceResult, in document: CADDocument) -> String {
        let name = "\(instance.name) (\(document.part(id: instance.part)?.name ?? "missing part"))"
        guard instance.status == .ok else { return "\(name): \(instance.status)" }
        let metrics = instance.bodies.compactMap(\.metrics)
        guard metrics.count == instance.bodies.count, let first = metrics.first else {
            return "\(name): ok, bounds unknown"
        }
        let low = metrics.dropFirst().reduce(first.boundsMin) { pointwiseMin($0, $1.boundsMin) }
        let high = metrics.dropFirst().reduce(first.boundsMax) { pointwiseMax($0, $1.boundsMax) }
        return "\(name): ok, bounds \(Format.point(low)) to \(Format.point(high))"
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
                if Self.isSound(body), let previous = old[key], Self.describe(previous, in: part.name) == line,
                    !featuresChanged(body: body.name, part: part.id)
                {
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
        lines += Self.capped(changed, "changed bodies", then: "call measure for their sizes")
        if !unchanged.isEmpty { lines.append("Unchanged bodies: \(Self.names(unchanged))") }
        if !removed.isEmpty { lines.append("Removed bodies: \(Self.names(removed))") }
        return lines
    }

    /// Whether an edit touched a feature that builds, changes or reads the body, or changed the value of one of
    /// their numeric fields through a parameter. The body's size alone cannot tell: a moved hole keeps the volume.
    private func featuresChanged(body: String, part id: UUID) -> Bool {
        guard let oldPart = before.parts.first(where: { $0.id == id }),
            let newPart = after.parts.first(where: { $0.id == id })
        else { return true }
        func touching(_ part: Part) -> [Feature] {
            let affected = part.affectedBodies()
            return part.features.filter { affected[$0.id] == body || $0.kind.bodyReferences.contains(body) }
        }
        let features = touching(newPart)
        guard touching(oldPart) == features else { return true }
        let (oldTable, newTable) = (ParameterTable(before.parameters), ParameterTable(after.parameters))
        return features.contains { feature in
            feature.kind.scalarFields.contains { _, scalar in
                (try? oldTable.evaluate(scalar)) != (try? newTable.evaluate(scalar))
            }
        }
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

    /// Parameters added ("+ name = expression"), changed ("name: old → new"), whose value moved through another
    /// parameter ("name = expression: old → new"), then removed ("- name"). Unchanged parameters are left out.
    static func parameterChanges(_ old: [Parameter], _ new: [Parameter]) -> [String] {
        let oldTable = Dictionary(
            ParameterTable(old).parameters.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let newParameters = ParameterTable(new).parameters
        let newNames = Set(newParameters.map(\.name))
        func value(_ parameter: EvaluatedParameter) -> String {
            switch parameter.value {
            case .success(let value): Format.number(value)
            case .failure(let error): "error: \(error)"
            }
        }
        let changes = newParameters.compactMap { parameter -> String? in
            guard let previous = oldTable[parameter.name] else {
                return "+ \(parameter.name) = \(DocumentListing.expression(parameter))"
            }
            if previous.expression != parameter.expression {
                return
                    "\(parameter.name): \(DocumentListing.expression(previous)) → \(DocumentListing.expression(parameter))"
            }
            guard value(previous) != value(parameter) else { return nil }
            return "\(parameter.name) = \(parameter.expression): \(value(previous)) → \(value(parameter))"
        }
        let removed = ParameterTable(old).parameters.filter { !newNames.contains($0.name) }.map { "- \($0.name)" }
        return changes + removed
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
    var instance: UUID?
    var joint: UUID?
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
            summary: focus.summary, focus: focus.feature, instanceFocus: focus.instance, jointFocus: focus.joint,
            notes: notes,
            referenceNotes: focus.referenceNotes,
            before: before,
            beforeResult: beforeResult, after: after, afterResult: afterResult)
        return .success(report.render())
    }
}
