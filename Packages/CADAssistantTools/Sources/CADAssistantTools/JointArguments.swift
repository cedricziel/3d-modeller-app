import CADModel
import Foundation
import SwiftUIAssistant

enum JointArguments {
    static func kind(_ text: String) throws(ToolError) -> JointKind {
        guard let kind = JointKind(rawValue: text) else {
            let kinds = JointKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw ToolError("Unknown joint kind '\(text)'. Kinds: \(kinds).")
        }
        return kind
    }

    /// One side, `{instance, body?, face, edge?, offset?}`, checked against the current rebuild when there is one.
    static func side(
        _ object: [String: JSONValue], _ label: String, in document: CADDocument, result: RebuildResult?
    ) throws(ToolError) -> JointFrameRef {
        do throws(ToolError) {
            let arguments = try Arguments(object, allowed: ["instance", "body", "face", "edge", "offset"])
            let instance = document.instances[
                try document.instanceIndex(named: try arguments.requiredString("instance"))]
            let body = try arguments.string("body")
            let face = GeometryReference(parsing: try arguments.requiredString("face"))
            let edge = try arguments.string("edge").map(GeometryReference.init(parsing:))
            let offset = try arguments.object("offset").map { (object) throws(ToolError) in try Self.offset(object) }
            if let placed = result?.assembly?.instance(id: instance.id) {
                let partBodies = result?.parts.first { $0.id == instance.part }?.bodies ?? []
                let built = placed.unmoved(partBodies: partBodies)
                let parameters = result?.parameters ?? ParameterTable(document.parameters)
                do throws(ReferenceError) {
                    let element = try built.element(face, .faces, body: body, parameters: parameters)
                    if let edge { _ = try built.element(edge, .edges, body: element.body, parameters: parameters) }
                } catch {
                    throw ToolError(error.description)
                }
            }
            return JointFrameRef(instance: instance.id, body: body, face: face, edge: edge, offset: offset)
        } catch {
            throw ToolError("\(label): \(error.description)")
        }
    }

    private static func offset(_ object: [String: JSONValue]) throws(ToolError) -> JointOffset {
        let arguments = try Arguments(object, allowed: ["x", "y", "z", "angle"])
        return JointOffset(
            x: try arguments.scalar("x") ?? 0, y: try arguments.scalar("y") ?? 0, z: try arguments.scalar("z") ?? 0,
            angle: try arguments.scalar("angle") ?? 0)
    }

    static let sideSchema: [String: JSONValue] = [
        "type": "object",
        "properties": [
            "instance": ["type": "string", "description": "The instance's name."],
            "body": [
                "type": "string", "description": "One body of the instance; only when the face name is in several.",
            ],
            "face": [
                "type": "string",
                "description": .string(
                    "A planar face (frame z = outward normal) or a cylindrical, conical or toroidal face "
                        + "(z = its axis), by the part's face name or a filter."),
            ],
            "edge": [
                "type": "string",
                "description": .string(
                    "An edge of the same body: a circle moves the origin to its centre, a line to its "
                        + "midpoint and turns x along it."),
            ],
            "offset": [
                "type": "object",
                "description": .string(
                    "Moves the frame by x, y, z (mm) along its own axes, then turns it by angle (degrees) "
                        + "about its z axis."),
                "properties": [
                    "x": .object(ToolSchemas.scalar), "y": .object(ToolSchemas.scalar),
                    "z": .object(ToolSchemas.scalar),
                    "angle": .object(ToolSchemas.scalar),
                ],
                "additionalProperties": false,
            ],
        ],
        "required": ["instance", "face"],
        "additionalProperties": false,
    ]
}

extension CADDocument {
    func jointIndex(named name: String) throws(ToolError) -> Int {
        guard let index = joints.firstIndex(where: { $0.name == name }) else {
            let names = joints.map(\.name).joined(separator: ", ")
            throw ToolError("No joint named '\(name)'. Joints: \(names.isEmpty ? "none" : names).")
        }
        return index
    }
}

extension CADDocument {
    /// Renames `old.` prefixes in the joint references on instances of `part`; returns a note per changed joint.
    mutating func renameJointReferences(part: UUID, from old: String, to new: String) -> [String] {
        guard let assembly else { return [] }
        let onPart = Set(assembly.instances.filter { $0.part == part }.map(\.id))
        var notes: [String] = []
        for index in assembly.joints.indices {
            var joint = assembly.joints[index]
            var changes: [String] = []
            for keyPath in [\Joint.a, \Joint.b] where onPart.contains(joint[keyPath: keyPath].instance) {
                var side = joint[keyPath: keyPath]
                let renamed = side.face.renamingFeature(old, to: new)
                if renamed != side.face { changes.append("\(renamed) (was \(side.face))") }
                side.face = renamed
                if let edge = side.edge {
                    let renamedEdge = edge.renamingFeature(old, to: new)
                    if renamedEdge != edge { changes.append("\(renamedEdge) (was \(edge))") }
                    side.edge = renamedEdge
                }
                joint[keyPath: keyPath] = side
            }
            guard !changes.isEmpty else { continue }
            self.assembly?.joints[index] = joint
            notes.append("\(joint.name) now refers to \(changes.joined(separator: ", "))")
        }
        return notes
    }
}
