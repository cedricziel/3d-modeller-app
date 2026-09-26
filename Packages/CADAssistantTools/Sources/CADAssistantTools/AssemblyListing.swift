import CADModel

enum AssemblyListing {
    static func lines(_ document: CADDocument, result: RebuildResult?) -> [String] {
        guard let assembly = document.assembly else { return [] }
        guard !assembly.instances.isEmpty else { return ["assembly", "  (no instances)"] }
        var lines = ["assembly"] + assembly.instances.map { "  " + line($0, document, result: result) }
        if !assembly.joints.isEmpty {
            lines.append("  joints")
            lines += assembly.joints.map { "    " + line($0, document, result: result) }
        }
        return lines
    }

    static func line(_ instance: Instance, _ document: CADDocument, result: RebuildResult?) -> String {
        let built = result?.assembly?.instance(id: instance.id)
        let status = built?.status.description ?? "not built"
        let solved = built.flatMap { built in
            built.movedByJoints ? built.transform.map { " → solved \(WriteReport.pose($0))" } : nil
        }
        return "\(instance.name)  \(summary(instance, document))\(solved ?? "")  \(status)"
    }

    static func line(_ joint: Joint, _ document: CADDocument, result: RebuildResult?) -> String {
        let status = result?.assembly?.joint(id: joint.id)?.status.description ?? "not built"
        let sides = "\(side(joint.a, document)) ↔ \(side(joint.b, document))"
        return "\(joint.name)  \(joint.kind.rawValue) \(sides)\(joint.flip ? ", flipped" : "")  \(status)"
    }

    private static func side(_ side: JointFrameRef, _ document: CADDocument) -> String {
        let instance = document.instances.first { $0.id == side.instance }?.name ?? "(missing instance)"
        var text = instance + (side.body.map { "/\($0)" } ?? "") + " \(side.face)"
        if let edge = side.edge { text += " at \(edge)" }
        if let offset = side.offset {
            let zero = Scalar.number(0)
            if [offset.x, offset.y, offset.z].contains(where: { $0 != zero }) {
                text += " offset \(Format.vector(Vector3(offset.x, offset.y, offset.z)))"
            }
            if offset.angle != zero { text += " turned \(Format.operand(offset.angle))°" }
        }
        return text
    }

    static func summary(_ instance: Instance, _ document: CADDocument) -> String {
        guard let part = document.part(id: instance.part) else { return "(missing part)" }
        let placed = part.name + (instance.body.map { "/\($0)" } ?? "")
        return "\(placed) \(DocumentListing.location(instance.placement))" + (instance.grounded ? ", grounded" : "")
    }
}
