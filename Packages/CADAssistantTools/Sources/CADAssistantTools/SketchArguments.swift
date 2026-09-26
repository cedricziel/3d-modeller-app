import CADModel
import SwiftUIAssistant

/// Entities, constraints and planes of the sketch tools, read from JSON arguments.
enum SketchArguments {
    static let entityKeys = [
        "name", "type", "at", "start", "end", "center", "radius", "startAngle", "endAngle", "construction",
    ]
    static let constraintKeys = ["name", "type", "entities", "points", "value", "at"]
    static let entityTypes = ["point", "line", "circle", "arc"]

    /// An entity whose name is empty when the caller gave none.
    static func entity(_ value: JSONValue, _ key: String) throws(ToolError) -> SketchEntity {
        guard let object = value.objectValue else { throw ToolError("Each of '\(key)' must be an object.") }
        let arguments = try Arguments(object, allowed: entityKeys)
        let type = try arguments.requiredString("type")
        func point(_ field: String) throws(ToolError) -> SketchPoint2 {
            guard let value = object[field], !value.isNull else {
                throw ToolError("A \(type) needs '\(field)' as [x, y].")
            }
            return try Self.point(value, field)
        }
        func number(_ field: String) throws(ToolError) -> Double {
            guard let value = object[field], let number = Self.number(value) else {
                throw ToolError("A \(type) needs '\(field)' as a number.")
            }
            return number
        }
        let geometry: SketchEntityGeometry
        switch type {
        case "point": geometry = .point(try point("at"))
        case "line": geometry = .line(start: try point("start"), end: try point("end"))
        case "circle": geometry = .circle(center: try point("center"), radius: try number("radius"))
        case "arc":
            geometry = .arc(
                center: try point("center"), radius: try number("radius"), startAngle: try number("startAngle"),
                endAngle: try number("endAngle"))
        default:
            throw ToolError("Unknown entity type '\(type)'. Types: \(entityTypes.joined(separator: ", ")).")
        }
        let name = try arguments.string("name") ?? ""
        if !name.isEmpty { try checkName(name, "entity") }
        return SketchEntity(name: name, geometry, construction: try arguments.bool("construction") ?? false)
    }

    /// A constraint whose name is empty when the caller gave none.
    static func constraint(_ value: JSONValue, _ key: String) throws(ToolError) -> SketchConstraint {
        guard let object = value.objectValue else { throw ToolError("Each of '\(key)' must be an object.") }
        let arguments = try Arguments(object, allowed: constraintKeys)
        let type = try arguments.requiredString("type")
        guard let kind = SketchConstraintKind(rawValue: type) else {
            throw ToolError(
                "Unknown constraint type '\(type)'. Types: "
                    + SketchConstraintKind.allCases.map(\.rawValue).joined(separator: ", ") + ".")
        }
        var at: [Scalar]?
        if let items = object["at"], !items.isNull {
            guard let values = items.arrayValue, values.count == 2 else { throw ToolError("'at' must be [x, y].") }
            at = try values.map { (item) throws(ToolError) in try Arguments.scalar(item, "at") }
        }
        let name = try arguments.string("name") ?? ""
        if !name.isEmpty { try checkName(name, "constraint") }
        return SketchConstraint(
            name: name, kind, entities: try arguments.strings("entities", "entity names") ?? [],
            points: try arguments.strings("points", "point names such as line1.end") ?? [],
            value: try arguments.scalar("value"), at: at)
    }

    static func list<T>(_ arguments: Arguments, _ key: String, _ read: (JSONValue, String) throws(ToolError) -> T)
        throws(ToolError) -> [T]?
    {
        guard let value = try arguments.array(key) else { return nil }
        var items: [T] = []
        for item in value { items.append(try read(item, key)) }
        return items
    }

    /// The plane from 'plane', 'body' and 'offset'; a face plane without 'body' uses the part's only body.
    static func plane(_ arguments: Arguments, part: Part, current: SketchPlane? = nil) throws(ToolError) -> SketchPlane?
    {
        let offset = try arguments.scalar("offset")
        guard let text = try arguments.string("plane") else {
            guard let current else {
                throw ToolError("A sketch needs 'plane': XY, XZ, YZ, or a face name such as Box1.top with 'body'.")
            }
            guard offset != nil || arguments.has("body") else { return nil }
            switch current {
            case .base(let base, let old): return .base(base, offset: offset ?? old)
            case .face(let body, let face, let old):
                return .face(body: try arguments.string("body") ?? body, face: face, offset: offset ?? old)
            }
        }
        if let base = SketchBasePlane(rawValue: text.uppercased()) {
            if arguments.has("body") { throw ToolError("'body' is only for a sketch on a face, not on \(text).") }
            return .base(base, offset: offset ?? 0)
        }
        let bodies = part.createdBodies().keys.sorted()
        guard let body = try arguments.string("body") ?? (bodies.count == 1 ? bodies[0] : nil) else {
            throw ToolError(
                "A sketch on the face \(text) needs 'body', the body the face belongs to. Bodies: "
                    + (bodies.isEmpty ? "none" : bodies.joined(separator: ", ")) + ".")
        }
        return .face(body: body, face: GeometryReference(parsing: text), offset: offset ?? 0)
    }

    /// Gives every unnamed entity `<type><n>` and every unnamed constraint `c<n>`, counting on from the highest.
    static func name(_ entities: inout [SketchEntity], existing: [SketchEntity], retired: [String] = []) {
        var taken = existing.map(\.name) + entities.map(\.name) + retired
        for index in entities.indices where entities[index].name.isEmpty {
            let name = next(entities[index].geometry.typeName, taken)
            entities[index].name = name
            taken.append(name)
        }
    }

    static func name(_ constraints: inout [SketchConstraint], existing: [SketchConstraint], retired: [String] = []) {
        var taken = existing.map(\.name) + constraints.map(\.name) + retired
        for index in constraints.indices where constraints[index].name.isEmpty {
            let name = next("c", taken)
            constraints[index].name = name
            taken.append(name)
        }
    }

    static func next(_ prefix: String, _ taken: [String]) -> String {
        let numbers = taken.compactMap { name -> Int? in
            guard name.hasPrefix(prefix) else { return nil }
            return Int(name.dropFirst(prefix.count))
        }
        return "\(prefix)\((numbers.max() ?? 0) + 1)"
    }

    static func checkName(_ name: String, _ what: String) throws(ToolError) {
        guard Naming.isIdentifier(name) else {
            throw ToolError("'\(name)' is not a valid \(what) name: use letters, digits and _, starting with a letter.")
        }
    }

    static func point(_ value: JSONValue, _ key: String) throws(ToolError) -> SketchPoint2 {
        guard let items = value.arrayValue, items.count == 2, let x = number(items[0]), let y = number(items[1]) else {
            throw ToolError("'\(key)' must be [x, y] in mm.")
        }
        return SketchPoint2(x, y)
    }

    static func number(_ value: JSONValue) -> Double? {
        switch value {
        case .number(let number) where number.isFinite: number
        case .integer(let integer): Double(integer)
        default: nil
        }
    }
}
