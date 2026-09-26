import CADModel
import SwiftUIAssistant

extension FeatureSpec {
    static let sketchKeys = ["sketch", "regions", "extent", "reversed", "face", "axis", "referenceBody"]
    static let extents = ["distance", "symmetric", "throughAll", "upToFace"]

    var sketchKeysGiven: [String] {
        [
            ("sketch", sketch != nil), ("regions", regions != nil), ("extent", extent != nil),
            ("reversed", reversed != nil), ("face", face != nil), ("axis", axis != nil),
            ("referenceBody", referenceBody != nil),
        ].filter(\.1).map(\.0)
    }

    mutating func readSketchFields(_ arguments: Arguments) throws(ToolError) {
        sketch = try arguments.string("sketch")
        regions = try arguments.strings("regions", "entity names")
        extent = try arguments.string("extent")
        reversed = try arguments.bool("reversed")
        face = try arguments.string("face").map(GeometryReference.init(parsing:))
        axis = try arguments.string("axis")
        referenceBody = try arguments.string("referenceBody")
    }

    mutating func setExtrude(_ extrude: ExtrudeFeature) {
        (type, sketch, regions, reversed) = ("extrude", extrude.sketch, extrude.regions, extrude.reversed)
        switch extrude.extent {
        case .distance(let value): (extent, dimensions) = ("distance", ["distance": value])
        case .symmetric(let value): (extent, dimensions) = ("symmetric", ["distance": value])
        case .throughAll: extent = "throughAll"
        case .upToFace(let body, let reference): (extent, face, referenceBody) = ("upToFace", reference, body)
        }
        setOperation(extrude.operation)
    }

    mutating func setRevolve(_ revolve: RevolveFeature) {
        (type, sketch, regions) = ("revolve", revolve.sketch, revolve.regions)
        dimensions = ["angle": revolve.angle]
        switch revolve.axis {
        case .sketchLine(let line): axis = line
        case .x: axis = "X"
        case .y: axis = "Y"
        case .z: axis = "Z"
        case .edge(let body, let edge): (axis, referenceBody) = (edge.text, body)
        }
        setOperation(revolve.operation)
    }

    private mutating func setOperation(_ solidOperation: SolidOperation) {
        switch solidOperation {
        case .newBody: operation = "newBody"
        case .join(let target): (operation, body) = ("join", target)
        case .cut(let target): (operation, body) = ("cut", target)
        case .intersect(let target): (operation, body) = ("intersect", target)
        }
    }

    func extrudeKind(given: FeatureSpec) throws(ToolError) -> FeatureKind {
        try given.reject(placement: true, tools: true, references: true, type: "extrude")
        try given.rejectKeys(["axis": given.axis != nil], type: "an extrude")
        try given.rejectDimensions(except: "distance", type: "an extrude")
        guard let sketch else { throw ToolError("An extrude needs 'sketch', the name of a sketch feature.") }
        let extentName = extent ?? "distance"
        guard Self.extents.contains(extentName) else {
            throw ToolError("'extent' is one of \(Self.extents.joined(separator: ", ")), not '\(extentName)'.")
        }
        let operation = try solidOperation(given: given)
        let extent: ExtrudeExtent
        switch extentName {
        case "distance", "symmetric":
            try given.rejectKeys(["face": given.face != nil], type: "a \(extentName) extrude")
            guard let value = dimensions["distance"] else { throw ToolError("An extrude needs 'distance' in mm.") }
            extent = extentName == "distance" ? .distance(value) : .symmetric(value)
        case "throughAll":
            try given.rejectKeys(
                ["distance": given.dimensions["distance"] != nil, "face": given.face != nil],
                type: "an extrude through all")
            guard operation != .newBody else {
                throw ToolError("An extrude through all needs operation cut, join or intersect with 'body'.")
            }
            extent = .throughAll
        default:
            try given.rejectKeys(["distance": given.dimensions["distance"] != nil], type: "an extrude up to a face")
            guard let face else {
                throw ToolError("An extrude up to a face needs 'face', a face name or filter matching one face.")
            }
            guard let owner = referenceBody ?? operation.targetBody else {
                throw ToolError("An extrude up to a face needs 'referenceBody', the body the face belongs to.")
            }
            extent = .upToFace(body: owner, face: face)
        }
        return .extrude(
            ExtrudeFeature(
                sketch: sketch, regions: regions ?? [], extent: extent, reversed: reversed ?? false,
                operation: operation))
    }

    func revolveKind(given: FeatureSpec) throws(ToolError) -> FeatureKind {
        try given.reject(placement: true, tools: true, references: true, type: "revolve")
        try given.rejectKeys(
            ["extent": given.extent != nil, "face": given.face != nil, "reversed": given.reversed != nil],
            type: "a revolve")
        try given.rejectDimensions(except: "angle", type: "a revolve")
        guard let sketch else { throw ToolError("A revolve needs 'sketch', the name of a sketch feature.") }
        guard let axis else {
            throw ToolError(
                "A revolve needs 'axis': a line of the sketch such as line5, X, Y or Z, or an edge name with "
                    + "'referenceBody'.")
        }
        let operation = try solidOperation(given: given)
        let revolveAxis: RevolveAxis
        switch axis.uppercased() {
        case "X": revolveAxis = .x
        case "Y": revolveAxis = .y
        case "Z": revolveAxis = .z
        default:
            let reference = GeometryReference(parsing: axis)
            if axis.hasPrefix("edge(") || { if case .filter = reference { true } else { false } }() {
                guard let owner = referenceBody ?? operation.targetBody else {
                    throw ToolError("An edge axis needs 'referenceBody', the body the edge belongs to.")
                }
                revolveAxis = .edge(body: owner, edge: reference)
            } else {
                revolveAxis = .sketchLine(axis)
            }
        }
        return .revolve(
            RevolveFeature(
                sketch: sketch, regions: regions ?? [], axis: revolveAxis, angle: dimensions["angle"] ?? 360,
                operation: operation))
    }

    private func rejectKeys(_ keys: [String: Bool], type: String) throws(ToolError) {
        if let key = keys.filter(\.value).keys.sorted().first {
            throw ToolError("\(type.prefix(1).uppercased() + type.dropFirst()) does not take '\(key)'.")
        }
    }

    private func rejectDimensions(except allowed: String, type: String) throws(ToolError) {
        if let extra = dimensions.keys.sorted().first(where: { $0 != allowed }) {
            throw ToolError("\(type.prefix(1).uppercased() + type.dropFirst()) does not take '\(extra)'.")
        }
    }
}
