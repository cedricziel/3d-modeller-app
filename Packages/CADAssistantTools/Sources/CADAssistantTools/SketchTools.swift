import CADModel
import Foundation
import SwiftUIAssistant

public struct AddSketchTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "add_sketch"

    public let description = """
        Adds a sketch: 2D entities on a plane, tied down by constraints, solved on every rebuild. Give the whole \
        sketch in one call. Coordinates are the sketch's own x and y in mm, angles in degrees. Entities (lines, \
        arcs, circles, points) are named line1, arc1, circle1, point1… unless you name them; constraints c1, c2…. \
        Points are line1.start, line1.end, arc1.start, arc1.end, arc1.center, circle1.center or a point entity's \
        name. Closed loops of non-construction entities become regions for extrude and revolve. Returns the \
        solve state (fully, under- or over-constrained), the solved coordinates, and the write report.
        """

    public var parameters: [ToolParameter] {
        [
            ToolSchemas.part,
            .optionalString("name", description: "Unique feature name; defaults to Sketch<n>."),
            .optionalString("before", description: "Insert before this feature."),
            .optionalString("after", description: "Insert after this feature."),
        ] + SketchSchemas.plane(required: true) + [
            .custom(
                "entities", description: SketchSchemas.entitiesDescription, required: true,
                schema: SketchSchemas.entityArray),
            .custom(
                "constraints", description: SketchSchemas.constraintsDescription,
                schema: SketchSchemas.constraintArray),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.addSketch(arguments)
    }
}

public struct EditSketchTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "edit_sketch"

    public let description = """
        Changes a sketch: its plane, entities and constraints. Removing an entity also removes the constraints that \
        use it. set_values changes constraint values ({"c3": 40} or an expression). update_entities replaces the \
        starting geometry of named entities, for example to move a guess the solver resolved the wrong way. Returns \
        the solve state, the solved coordinates, and the write report.
        """

    public var parameters: [ToolParameter] {
        [.string("sketch", description: "The sketch feature."), ToolSchemas.part]
            + SketchSchemas.plane(required: false) + [
                .custom(
                    "add_entities", description: SketchSchemas.entitiesDescription, schema: SketchSchemas.entityArray),
                .custom(
                    "update_entities", description: "Entities with 'name' whose geometry replaces the stored one.",
                    schema: SketchSchemas.entityArray),
                .custom(
                    "remove_entities", description: "Entity names to remove.",
                    schema: ["type": "array", "items": ["type": "string"]]),
                .custom(
                    "add_constraints", description: SketchSchemas.constraintsDescription,
                    schema: SketchSchemas.constraintArray),
                .custom(
                    "remove_constraints", description: "Constraint names to remove.",
                    schema: ["type": "array", "items": ["type": "string"]]),
                .custom(
                    "set_values", description: "New values by constraint name, numbers or expressions.",
                    schema: ["type": "object", "additionalProperties": .object(ToolSchemas.scalar)]),
            ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.editSketch(arguments)
    }
}

public struct GetSketchTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "get_sketch"

    public let description = """
        Shows a sketch: its plane and axes in model space, the solve state, every entity with its solved \
        coordinates, every constraint, and where the profile is open or ambiguous.
        """

    public var parameters: [ToolParameter] {
        [.string("sketch", description: "The sketch feature."), ToolSchemas.part]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.getSketch(arguments)
    }
}

enum SketchSchemas {
    static func plane(required: Bool) -> [ToolParameter] {
        [
            .custom(
                "plane",
                description: """
                    XY (x = X, y = Y, normal +Z), XZ (x = X, y = Z, normal -Y), YZ (x = Y, y = Z, normal +X), or a \
                    planar face name such as Box1.top (normal out of the body; x follows world X, else Y).
                    """, required: required, schema: ["type": "string"]),
            .optionalString("body", description: "The body a face plane belongs to; defaults to the only body."),
            ToolSchemas.scalar("offset", "Moves the plane along its normal, in mm."),
        ]
    }

    static let entitiesDescription = """
        Each {type, name?, construction?, …}: point {at: [x, y]}, line {start, end}, circle {center, radius}, arc \
        {center, radius, startAngle, endAngle} (degrees, counter-clockwise). Construction entities guide \
        constraints but form no profile.
        """

    static let constraintsDescription = """
        Each {type, name?, entities?, points?, value?, at?}. coincident, tangentAt: 2 points. horizontal, vertical: \
        1 line. parallel, perpendicular: 2 lines. tangent: 2 curves (line and arc/circle, or two arcs/circles). \
        equal: 2 lines or 2 arcs/circles. distance: 2 points, value. pointLineDistance: 1 point, 1 line, value. \
        angle: 2 lines, value in degrees. radius, diameter: 1 arc/circle, value. fixed: 1 point, optional at: \
        [x, y]. pointOnLine: 1 point, 1 line. pointOnCircle: 1 point, 1 arc/circle. Values may be expressions.
        """

    static let entityArray: [String: JSONValue] = ["type": "array", "items": ["type": "object"]]
    static let constraintArray: [String: JSONValue] = ["type": "array", "items": ["type": "object"]]
}

extension CADSession {
    func addSketch(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        var id: UUID?
        let result = await write { (document) throws(ToolError) in
            let arguments = try Arguments(
                raw,
                allowed: ["part", "name", "before", "after", "plane", "body", "offset", "entities", "constraints"])
            let partIndex = try document.partIndex(named: try arguments.string("part"))
            let part = document.parts[partIndex]
            let plane = try SketchArguments.plane(arguments, part: part)!
            var entities = try SketchArguments.list(arguments, "entities", SketchArguments.entity) ?? []
            var constraints = try SketchArguments.list(arguments, "constraints", SketchArguments.constraint) ?? []
            SketchArguments.name(&entities, existing: [])
            SketchArguments.name(&constraints, existing: [])
            let sketch = SketchFeature(plane: plane, entities: entities, constraints: constraints)
            try Self.check(sketch, document)
            let name = try arguments.string("name") ?? SketchArguments.next("Sketch", part.features.map(\.name))
            try Naming.checkFeatureName(name, in: part)
            let index = try Self.insertionIndex(arguments, in: part)
            let feature = Feature(name: name, kind: .sketch(sketch))
            document.parts[partIndex].features.insert(feature, at: index)
            id = feature.id
            return WriteFocus(
                actionName: "Add \(name)", summary: "Added \(name) to part \(part.name)", feature: feature.id)
        }
        return withSketch(result, id: id)
    }

    func editSketch(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        var id: UUID?
        let result = await write { (document) throws(ToolError) in
            let arguments = try Arguments(
                raw,
                allowed: [
                    "sketch", "part", "plane", "body", "offset", "add_entities", "update_entities", "remove_entities",
                    "add_constraints", "remove_constraints", "set_values",
                ])
            let location = try document.featureLocation(
                named: try arguments.requiredString("sketch"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features[location.feature]
            guard case .sketch(var sketch) = feature.kind else {
                throw ToolError("\(feature.name) is not a sketch; use edit_feature for it.")
            }
            let edit = try SketchEdit(arguments, part: document.parts[location.part])
            guard !edit.isEmpty else {
                throw ToolError(
                    "Give at least one change: plane, body, offset, add_entities, update_entities, remove_entities, "
                        + "add_constraints, remove_constraints or set_values.")
            }
            let changes = try edit.apply(to: &sketch)
            try Self.check(sketch, document)
            document.parts[location.part].features[location.feature].kind = .sketch(sketch)
            id = feature.id
            return WriteFocus(
                actionName: "Edit \(feature.name)", summary: "Edited \(feature.name): \(changes)", feature: feature.id)
        }
        return withSketch(result, id: id)
    }

    func getSketch(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        do throws(ToolError) {
            let arguments = try Arguments(raw, allowed: ["sketch", "part"])
            let location = try document.featureLocation(
                named: try arguments.requiredString("sketch"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features[location.feature]
            guard case .sketch = feature.kind else { throw ToolError("\(feature.name) is not a sketch.") }
            let result = await currentResult()
            return .success(SketchReport.render(feature, result: result))
        } catch {
            return .failure(error.description)
        }
    }

    private func withSketch(_ result: ToolExecutionResult, id: UUID?) -> ToolExecutionResult {
        guard result.success, let id, let feature = document.feature(id: id) else { return result }
        return .success(
            result.message + "\n\n" + SketchReport.render(feature, result: isResultCurrent ? self.result : nil))
    }

    private static func check(_ sketch: SketchFeature, _ document: CADDocument) throws(ToolError) {
        do throws(FeatureError) {
            try sketch.check(parameters: ParameterTable(document.parameters))
        } catch {
            throw ToolError("Nothing changed: \(error)")
        }
    }

    static func insertionIndex(_ arguments: Arguments, in part: Part) throws(ToolError) -> Int {
        func index(of name: String) throws(ToolError) -> Int {
            guard let index = part.features.firstIndex(where: { $0.name == name }) else {
                throw ToolError("No feature named '\(name)' in part \(part.name).")
            }
            return index
        }
        switch (try arguments.string("before"), try arguments.string("after")) {
        case (nil, nil): return part.features.endIndex
        case (let before?, nil): return try index(of: before)
        case (nil, let after?): return try index(of: after) + 1
        case (_?, _?): throw ToolError("Give 'before' or 'after', not both.")
        }
    }
}

/// The changes edit_sketch asks for.
struct SketchEdit {
    var changesPlane = false
    var added: [SketchEntity] = []
    var updated: [SketchEntity] = []
    var removed: [String] = []
    var addedConstraints: [SketchConstraint] = []
    var removedConstraints: [String] = []
    var values: [(String, Scalar)] = []

    init(_ arguments: Arguments, part: Part) throws(ToolError) {
        changesPlane = arguments.has("plane") || arguments.has("offset") || arguments.has("body")
        added = try SketchArguments.list(arguments, "add_entities", SketchArguments.entity) ?? []
        updated = try SketchArguments.list(arguments, "update_entities", SketchArguments.entity) ?? []
        removed = try arguments.strings("remove_entities", "entity names") ?? []
        addedConstraints = try SketchArguments.list(arguments, "add_constraints", SketchArguments.constraint) ?? []
        removedConstraints = try arguments.strings("remove_constraints", "constraint names") ?? []
        if let object = try arguments.object("set_values") {
            for key in object.keys.sorted() { values.append((key, try Arguments.scalar(object[key]!, key))) }
        }
        self.arguments = arguments
        self.part = part
    }

    private let arguments: Arguments
    private let part: Part

    var isEmpty: Bool {
        !changesPlane && added.isEmpty && updated.isEmpty && removed.isEmpty && addedConstraints.isEmpty
            && removedConstraints.isEmpty && values.isEmpty
    }

    /// Applies the changes and describes them.
    func apply(to sketch: inout SketchFeature) throws(ToolError) -> String {
        var notes: [String] = []
        if changesPlane {
            if let newPlane = try SketchArguments.plane(arguments, part: part, current: sketch.plane) {
                sketch.plane = newPlane
                notes.append("plane \(DocumentListing.planeText(newPlane))")
            }
        }
        for name in removed {
            guard let index = sketch.entities.firstIndex(where: { $0.name == name }) else {
                throw ToolError("\(Self.noEntity(name, sketch))")
            }
            sketch.entities.remove(at: index)
            let using = sketch.constraints.filter { $0.uses(name) }.map(\.name)
            sketch.constraints.removeAll { $0.uses(name) }
            notes.append("removed \(name)" + (using.isEmpty ? "" : " with \(using.joined(separator: ", "))"))
        }
        for name in removedConstraints {
            guard let index = sketch.constraints.firstIndex(where: { $0.name == name }) else {
                throw ToolError("\(Self.noConstraint(name, sketch))")
            }
            sketch.constraints.remove(at: index)
            notes.append("removed \(name)")
        }
        for entity in updated {
            guard let index = sketch.entities.firstIndex(where: { $0.name == entity.name }), !entity.name.isEmpty
            else {
                throw ToolError(
                    entity.name.isEmpty ? "Each of 'update_entities' needs 'name'." : Self.noEntity(entity.name, sketch)
                )
            }
            sketch.entities[index] = entity
        }
        var newEntities = added
        SketchArguments.name(&newEntities, existing: sketch.entities)
        for entity in newEntities where sketch.entities.contains(where: { $0.name == entity.name }) {
            throw ToolError("The sketch already has an entity named '\(entity.name)'.")
        }
        sketch.entities += newEntities
        var newConstraints = addedConstraints
        SketchArguments.name(&newConstraints, existing: sketch.constraints)
        for constraint in newConstraints where sketch.constraints.contains(where: { $0.name == constraint.name }) {
            throw ToolError("The sketch already has a constraint named '\(constraint.name)'.")
        }
        sketch.constraints += newConstraints
        for (name, value) in values {
            guard let index = sketch.constraints.firstIndex(where: { $0.name == name }) else {
                throw ToolError(Self.noConstraint(name, sketch))
            }
            guard sketch.constraints[index].kind.takesValue else {
                throw ToolError("\(name) (\(sketch.constraints[index].kind.rawValue)) takes no value.")
            }
            sketch.constraints[index].value = value
        }
        var parts: [String] = []
        let addedNames = newEntities.map(\.name) + newConstraints.map(\.name)
        if !addedNames.isEmpty { parts.append("added \(addedNames.joined(separator: ", "))") }
        if !updated.isEmpty { parts.append("updated \(updated.map(\.name).joined(separator: ", "))") }
        parts += notes
        if !values.isEmpty { parts.append("set " + values.map { "\($0.0) = \($0.1)" }.joined(separator: ", ")) }
        return parts.joined(separator: "; ")
    }

    private static func noEntity(_ name: String, _ sketch: SketchFeature) -> String {
        "The sketch has no entity named '\(name)'. Entities: \(sketch.entities.map(\.name).joined(separator: ", "))."
    }

    private static func noConstraint(_ name: String, _ sketch: SketchFeature) -> String {
        let names = sketch.constraints.map(\.name)
        return
            "The sketch has no constraint named '\(name)'. Constraints: \(names.isEmpty ? "none" : names.joined(separator: ", "))."
    }
}

extension SketchConstraint {
    func uses(_ entity: String) -> Bool {
        entities.contains(entity) || points.contains { $0 == entity || $0.hasPrefix(entity + ".") }
    }
}

extension SketchConstraintKind {
    var takesValue: Bool {
        switch self {
        case .distance, .pointLineDistance, .angle, .radius, .diameter: true
        default: false
        }
    }
}
