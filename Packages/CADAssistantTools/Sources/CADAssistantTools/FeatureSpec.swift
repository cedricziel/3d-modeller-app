import CADModel
import SwiftUIAssistant

/// The flat argument form of a feature kind shared by add_feature and edit_feature. Every field is optional so an
/// edit can carry only the fields it changes and be laid over the feature's current values.
struct FeatureSpec: Equatable {
    static let shapeDimensions: [String: [String]] = [
        "box": ["width", "depth", "height"],
        "cylinder": ["radius", "height"],
        "sphere": ["radius"],
        "cone": ["bottomRadius", "topRadius", "height"],
        "torus": ["majorRadius", "minorRadius"],
        "fillet": ["radius"],
        "chamfer": ["distance"],
        "shell": ["thickness"],
        "extrude": ["distance"],
        "revolve": ["angle"],
    ]
    static let types = [
        "box", "cylinder", "sphere", "cone", "torus", "boolean", "transform", "fillet", "chamfer", "shell", "extrude",
        "revolve",
    ]
    static let dimensionKeys = [
        "width", "depth", "height", "radius", "bottomRadius", "topRadius", "majorRadius", "minorRadius", "distance",
        "thickness", "angle",
    ]
    static let keys =
        ["type"] + dimensionKeys + ["placement", "operation", "body", "tools", "edges", "faces"] + sketchKeys
    static let solidOperations = ["newBody", "join", "cut", "intersect"]
    static let booleanOperations = ["union", "subtract", "intersect"]

    var type: String?
    var dimensions: [String: Scalar] = [:]
    var translation: [String: Scalar] = [:]
    var rotationAxis: [String: Scalar] = [:]
    var rotationDegrees: Scalar?
    var operation: String?
    var body: String?
    var tools: [String]?
    var edges: [GeometryReference]?
    var faces: [GeometryReference]?
    var sketch: String?
    var regions: [String]?
    var extent: String?
    var reversed: Bool?
    var face: GeometryReference?
    var axis: String?
    var referenceBody: String?

    init() {}

    init(_ kind: FeatureKind) {
        switch kind {
        case .primitive(let primitive):
            switch primitive.shape {
            case .box: type = "box"
            case .cylinder: type = "cylinder"
            case .sphere: type = "sphere"
            case .cone: type = "cone"
            case .torus: type = "torus"
            }
            dimensions = Dictionary(uniqueKeysWithValues: primitive.shape.scalarFields)
            setPlacement(primitive.placement)
            switch primitive.operation {
            case .newBody: operation = "newBody"
            case .join(let target): (operation, body) = ("join", target)
            case .cut(let target): (operation, body) = ("cut", target)
            case .intersect(let target): (operation, body) = ("intersect", target)
            }
        case .boolean(let boolean):
            (type, operation, body, tools) = ("boolean", boolean.operation.rawValue, boolean.target, boolean.tools)
        case .transform(let transform):
            (type, body) = ("transform", transform.body)
            setPlacement(transform.placement)
        case .fillet(let fillet):
            (type, body, edges) = ("fillet", fillet.body, fillet.edges)
            dimensions = ["radius": fillet.radius]
        case .chamfer(let chamfer):
            (type, body, edges) = ("chamfer", chamfer.body, chamfer.edges)
            dimensions = ["distance": chamfer.distance]
        case .shell(let shell):
            (type, body, faces) = ("shell", shell.body, shell.faces)
            dimensions = ["thickness": shell.thickness]
        case .sketch: type = "sketch"
        case .extrude(let extrude): setExtrude(extrude)
        case .revolve(let revolve): setRevolve(revolve)
        }
    }

    init(_ arguments: Arguments) throws(ToolError) {
        if let type = try arguments.string("type") {
            if type == "sketch" { throw ToolError("Use add_sketch to add a sketch and edit_sketch to change one.") }
            guard Self.types.contains(type) else {
                throw ToolError("Unknown type '\(type)'. Types: \(Self.types.joined(separator: ", ")).")
            }
            self.type = type
        }
        for key in Self.dimensionKeys {
            if let value = try arguments.scalar(key) { dimensions[key] = value }
        }
        if let placement = try arguments.object("placement") {
            let placementArguments = try Arguments(
                placement, allowed: ["translation", "rotationAxis", "rotationDegrees"])
            translation = try Self.vector(placement["translation"], "placement.translation")
            rotationAxis = try Self.vector(placement["rotationAxis"], "placement.rotationAxis")
            rotationDegrees = try placementArguments.scalar("rotationDegrees")
        }
        operation = try arguments.string("operation")
        body = try arguments.string("body")
        tools = try arguments.strings("tools", "body names")
        edges = try arguments.strings("edges", "edge names or filters")?.map(GeometryReference.init(parsing:))
        faces = try arguments.strings("faces", "face names or filters")?.map(GeometryReference.init(parsing:))
        try readSketchFields(arguments)
    }

    private static func vector(_ value: JSONValue?, _ key: String) throws(ToolError) -> [String: Scalar] {
        guard let value, !value.isNull else { return [:] }
        var components: [String: Scalar] = [:]
        if let items = value.arrayValue {
            guard items.count == 3 else { throw ToolError("'\(key)' must have x, y and z.") }
            for (axis, item) in zip(["x", "y", "z"], items) {
                components[axis] = try Arguments.scalar(item, "\(key).\(axis)")
            }
            return components
        }
        guard let object = value.objectValue else { throw ToolError("'\(key)' must be an object with x, y and z.") }
        let arguments = try Arguments(object, allowed: ["x", "y", "z"])
        for axis in ["x", "y", "z"] {
            if let scalar = try arguments.scalar(axis) { components[axis] = scalar }
        }
        return components
    }

    private mutating func setPlacement(_ placement: Placement) {
        translation = ["x": placement.translation.x, "y": placement.translation.y, "z": placement.translation.z]
        rotationAxis = ["x": placement.rotationAxis.x, "y": placement.rotationAxis.y, "z": placement.rotationAxis.z]
        rotationDegrees = placement.rotationDegrees
    }

    var isEmpty: Bool { self == FeatureSpec() }

    var hasPlacement: Bool { !translation.isEmpty || !rotationAxis.isEmpty || rotationDegrees != nil }

    /// These fields laid over `base`. Switching an operation to newBody drops the old target body.
    func overriding(_ base: FeatureSpec) -> FeatureSpec {
        var merged = base
        if let type { merged.type = type }
        merged.dimensions.merge(dimensions) { $1 }
        merged.translation.merge(translation) { $1 }
        merged.rotationAxis.merge(rotationAxis) { $1 }
        if let rotationDegrees { merged.rotationDegrees = rotationDegrees }
        if let operation {
            merged.operation = operation
            if operation == "newBody" { merged.body = nil }
        }
        if let body { merged.body = body }
        if let tools { merged.tools = tools }
        if let edges { merged.edges = edges }
        if let faces { merged.faces = faces }
        if let sketch { merged.sketch = sketch }
        if let regions { merged.regions = regions }
        if let extent { merged.extent = extent }
        if let reversed { merged.reversed = reversed }
        if let face { merged.face = face }
        if let axis { merged.axis = axis }
        if let referenceBody { merged.referenceBody = referenceBody }
        return merged
    }

    /// Builds the kind from these (merged) fields. `given` holds only what the caller passed, and is what
    /// fields that do not apply to the type are checked against.
    func kind(given: FeatureSpec) throws(ToolError) -> FeatureKind {
        guard let type else { throw ToolError("Missing 'type'. Types: \(Self.types.joined(separator: ", ")).") }
        if type == "sketch" { throw ToolError("Use edit_sketch to change a sketch.") }
        if type != "extrude" && type != "revolve", let key = given.sketchKeysGiven.first {
            throw ToolError("A \(type) does not take '\(key)'.")
        }
        let placement = Placement(
            translation: Vector3(translation["x"] ?? 0, translation["y"] ?? 0, translation["z"] ?? 0),
            rotationAxis: Vector3(rotationAxis["x"] ?? 0, rotationAxis["y"] ?? 0, rotationAxis["z"] ?? 1),
            rotationDegrees: rotationDegrees ?? 0)
        switch type {
        case "boolean":
            try given.reject(dimensions: true, placement: true, references: true, type: type)
            guard let operation, let booleanOperation = BooleanOperation(rawValue: operation) else {
                throw ToolError("A boolean needs 'operation': \(Self.booleanOperations.joined(separator: ", ")).")
            }
            guard let body else { throw ToolError("A boolean needs 'body', the target body.") }
            guard let tools, !tools.isEmpty else {
                throw ToolError("A boolean needs 'tools', a non-empty list of bodies.")
            }
            return .boolean(BooleanFeature(operation: booleanOperation, target: body, tools: tools))
        case "transform":
            try given.reject(dimensions: true, operation: true, tools: true, references: true, type: type)
            guard let body else { throw ToolError("A transform needs 'body', the body to move.") }
            return .transform(TransformFeature(body: body, placement: placement))
        case "fillet", "chamfer", "shell":
            return try dressUp(type, given: given)
        case "extrude":
            return try extrudeKind(given: given)
        case "revolve":
            return try revolveKind(given: given)
        default:
            try given.reject(tools: true, references: true, type: type)
            let names = Self.shapeDimensions[type] ?? []
            if let extra = given.dimensions.keys.sorted().first(where: { !names.contains($0) }) {
                throw ToolError("A \(type) does not take '\(extra)'; it takes \(names.joined(separator: ", ")).")
            }
            var values: [Scalar] = []
            for name in names {
                guard let value = dimensions[name] else { throw ToolError("A \(type) needs '\(name)'.") }
                values.append(value)
            }
            let shape: PrimitiveShape =
                switch type {
                case "box": .box(width: values[0], depth: values[1], height: values[2])
                case "cylinder": .cylinder(radius: values[0], height: values[1])
                case "sphere": .sphere(radius: values[0])
                case "cone": .cone(bottomRadius: values[0], topRadius: values[1], height: values[2])
                default: .torus(majorRadius: values[0], minorRadius: values[1])
                }
            return .primitive(
                PrimitiveFeature(shape, placement: placement, operation: try solidOperation(given: given)))
        }
    }

    private func dressUp(_ type: String, given: FeatureSpec) throws(ToolError) -> FeatureKind {
        let size = Self.shapeDimensions[type]![0]
        let referenceKey = type == "shell" ? "faces" : "edges"
        try given.reject(placement: true, operation: true, tools: true, type: type)
        if let extra = given.dimensions.keys.sorted().first(where: { $0 != size }) {
            throw ToolError("A \(type) does not take '\(extra)'; it takes \(size).")
        }
        if type == "shell" ? given.edges != nil : given.faces != nil {
            throw ToolError(
                "A \(type) does not take '\(type == "shell" ? "edges" : "faces")'; it takes '\(referenceKey)'.")
        }
        guard let body else { throw ToolError("A \(type) needs 'body', the body to change.") }
        guard let references = type == "shell" ? faces : edges, !references.isEmpty else {
            throw ToolError(
                "A \(type) needs '\(referenceKey)', a non-empty list of \(referenceKey == "faces" ? "face" : "edge") "
                    + "names or filters; call find_geometry to see them.")
        }
        // Naming the type (on add, or when an edit changes it) needs the size too, so a cylinder turned into a
        // fillet does not quietly keep the cylinder's radius.
        guard let value = given.type != nil ? given.dimensions[size] : dimensions[size] else {
            throw ToolError("A \(type) needs '\(size)'.")
        }
        return switch type {
        case "fillet": .fillet(FilletFeature(body: body, edges: references, radius: value))
        case "chamfer": .chamfer(ChamferFeature(body: body, edges: references, distance: value))
        default: .shell(ShellFeature(body: body, faces: references, thickness: value))
        }
    }

    func solidOperation(given: FeatureSpec) throws(ToolError) -> SolidOperation {
        switch operation ?? "newBody" {
        case "newBody":
            if given.body != nil {
                throw ToolError("'body' only applies to join, cut and intersect; newBody creates its own body.")
            }
            return .newBody
        case let mode where Self.solidOperations.contains(mode):
            guard let body else { throw ToolError("Operation \(mode) needs 'body', the body to \(mode).") }
            return mode == "join" ? .join(body) : mode == "cut" ? .cut(body) : .intersect(body)
        case let mode:
            throw ToolError(
                "A solid's 'operation' is one of \(Self.solidOperations.joined(separator: ", ")), not '\(mode)'.")
        }
    }

    func reject(
        dimensions rejectDimensions: Bool = false, placement: Bool = false, operation rejectOperation: Bool = false,
        tools rejectTools: Bool = false, references: Bool = false, type: String
    ) throws(ToolError) {
        var extra: [String] = []
        if rejectDimensions { extra += dimensions.keys.sorted() }
        if placement, hasPlacement { extra.append("placement") }
        if rejectOperation, operation != nil { extra.append("operation") }
        if rejectTools, tools != nil { extra.append("tools") }
        if references, edges != nil { extra.append("edges") }
        if references, faces != nil { extra.append("faces") }
        guard extra.isEmpty else {
            throw ToolError("A \(type) does not take \(extra.map { "'\($0)'" }.joined(separator: ", ")).")
        }
    }
}

extension ToolSchemas {
    static func kindParameters(typeRequired: Bool) -> [ToolParameter] {
        [
            .enumParameter(
                "type",
                description: """
                    Feature type. box: width along X, depth along Y, height along Z, one corner at the placement \
                    origin. cylinder: radius, height along +Z, base centred on the origin. sphere: radius, centred. \
                    cone: bottomRadius, topRadius, height along +Z. torus: majorRadius, minorRadius, centred, axis Z. \
                    boolean: combine bodies. transform: move or rotate a body. fillet: round 'edges' of 'body' by \
                    radius. chamfer: bevel 'edges' of 'body' by distance. shell: hollow 'body' with walls thickness \
                    thick inside it, open at 'faces'. extrude: sweep closed regions of 'sketch' along its plane's \
                    normal. revolve: turn closed regions of 'sketch' about 'axis'. Sketches themselves are added with \
                    add_sketch.
                    """,
                values: FeatureSpec.types, required: typeRequired),
            scalar("width", "Box size along X in mm."),
            scalar("depth", "Box size along Y in mm."),
            scalar("height", "Box, cylinder or cone height along Z in mm."),
            scalar("radius", "Cylinder or sphere radius, or fillet radius, in mm."),
            scalar("bottomRadius", "Cone radius at its base in mm."),
            scalar("topRadius", "Cone radius at its top in mm; 0 for a pointed cone."),
            scalar("majorRadius", "Torus radius from its centre to the tube centre in mm."),
            scalar("minorRadius", "Torus tube radius in mm."),
            scalar(
                "distance",
                "Chamfer distance on both faces in mm; extrude: how far along the sketch normal (distance and "
                    + "symmetric extents)."),
            scalar("thickness", "Shell wall thickness in mm, measured inward."),
            scalar("angle", "revolve: degrees, more than 0 and at most 360 (the default)."),
            .custom(
                "placement",
                description: """
                    Solids: where the solid sits. transform: how the body moves. The shape is rotated by \
                    rotationDegrees (degrees) about rotationAxis through the origin, then moved by translation (mm). \
                    Left-out values keep their current value, or the default: no move, axis Z, 0 degrees.
                    """,
                schema: placement),
            .enumParameter(
                "operation",
                description: """
                    Solids: newBody (default) creates a new body; join, cut and intersect combine the solid into the \
                    existing body named by 'body'. boolean: union, subtract or intersect the 'tools' bodies into 'body'.
                    """,
                values: FeatureSpec.solidOperations + ["union", "subtract"], required: false),
            .optionalString(
                "body",
                description: """
                    A body name such as Body1. Solids: the body to join, cut or intersect. boolean: the target body. \
                    transform: the body to move. fillet, chamfer, shell: the body to change.
                    """),
            .custom(
                "tools", description: "boolean only: the bodies combined into 'body'. They are used up.",
                schema: ["type": "array", "items": ["type": "string"]]),
            .custom(
                "edges",
                description: """
                    fillet and chamfer: the edges, each a name such as edge(Plate.front, Plate.top) or a filter such \
                    as "parallel Z and farthest +X" or "circular r=2.75". A name must match one edge; a filter may \
                    match several. Call find_geometry to see names.
                    """,
                schema: ["type": "array", "items": ["type": "string"]]),
            .custom(
                "faces",
                description: """
                    shell: the faces to open, each a name such as Plate.top or a filter such as "normal +Z".
                    """,
                schema: ["type": "array", "items": ["type": "string"]]),
            .optionalString("sketch", description: "extrude, revolve: the sketch feature whose closed regions to use."),
            .custom(
                "regions",
                description: """
                    extrude, revolve: which closed loops to use, each named by one entity of the loop (circle1); the \
                    loops directly inside a chosen loop become holes. Leave out for every region.
                    """,
                schema: ["type": "array", "items": ["type": "string"]]),
            .enumParameter(
                "extent",
                description: """
                    extrude: distance (default; 'distance' along the normal), symmetric ('distance' split to both \
                    sides), throughAll (through the whole target 'body', both sides; needs cut, join or intersect) or \
                    upToFace (to the planar 'face', parallel to the sketch).
                    """,
                values: FeatureSpec.extents, required: false),
            ToolParameter(
                name: "reversed", type: .boolean,
                description: "extrude: go against the sketch normal, e.g. to cut into the face the sketch lies on.",
                required: false),
            .optionalString(
                "face", description: "extrude upToFace: a face name or filter matching one planar face."),
            .optionalString(
                "axis",
                description: """
                    revolve: a line of the sketch (line5, often a construction line), X, Y or Z through the origin, \
                    or a straight edge name such as edge(Base.front, Base.left) with 'referenceBody'.
                    """),
            .optionalString(
                "referenceBody",
                description: "The body an upToFace 'face' or an edge 'axis' belongs to; defaults to 'body'."),
        ]
    }
}
