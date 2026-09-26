import Foundation

extension SketchPoint2: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Double.self)
        let y = try container.decode(Double.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A point is [x, y]")
        }
        self.init(x, y)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

extension SketchPlane: Codable {
    private enum CodingKeys: String, CodingKey { case base, body, face, offset }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let offset = try container.decodeIfPresent(Scalar.self, forKey: .offset) ?? 0
        if let base = try container.decodeIfPresent(SketchBasePlane.self, forKey: .base) {
            self = .base(base, offset: offset)
        } else {
            self = .face(
                body: try container.decode(String.self, forKey: .body),
                face: try container.decode(GeometryReference.self, forKey: .face), offset: offset)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .base(let base, _):
            try container.encode(base, forKey: .base)
        case .face(let body, let face, _):
            try container.encode(body, forKey: .body)
            try container.encode(face, forKey: .face)
        }
        try container.encode(offset, forKey: .offset)
    }
}

extension SketchEntity: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, type, at, start, end, center, radius, startAngle, endAngle, construction
    }

    private enum Kind: String, Codable { case point, line, circle, arc }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func point(_ key: CodingKeys) throws -> SketchPoint2 { try container.decode(SketchPoint2.self, forKey: key) }
        func number(_ key: CodingKeys) throws -> Double { try container.decode(Double.self, forKey: key) }
        let geometry: SketchEntityGeometry =
            switch try container.decode(Kind.self, forKey: .type) {
            case .point: .point(try point(.at))
            case .line: .line(start: try point(.start), end: try point(.end))
            case .circle: .circle(center: try point(.center), radius: try number(.radius))
            case .arc:
                .arc(
                    center: try point(.center), radius: try number(.radius), startAngle: try number(.startAngle),
                    endAngle: try number(.endAngle))
            }
        self.init(
            name: try container.decode(String.self, forKey: .name), geometry,
            construction: try container.decodeIfPresent(Bool.self, forKey: .construction) ?? false)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(geometry.typeName, forKey: .type)
        switch geometry {
        case .point(let at):
            try container.encode(at, forKey: .at)
        case .line(let start, let end):
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case .circle(let center, let radius):
            try container.encode(center, forKey: .center)
            try container.encode(radius, forKey: .radius)
        case .arc(let center, let radius, let startAngle, let endAngle):
            try container.encode(center, forKey: .center)
            try container.encode(radius, forKey: .radius)
            try container.encode(startAngle, forKey: .startAngle)
            try container.encode(endAngle, forKey: .endAngle)
        }
        if construction { try container.encode(true, forKey: .construction) }
    }
}

extension SketchConstraint: Codable {
    private enum CodingKeys: String, CodingKey { case name, type, entities, points, value, at }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            try container.decode(SketchConstraintKind.self, forKey: .type),
            entities: try container.decodeIfPresent([String].self, forKey: .entities) ?? [],
            points: try container.decodeIfPresent([String].self, forKey: .points) ?? [],
            value: try container.decodeIfPresent(Scalar.self, forKey: .value),
            at: try container.decodeIfPresent([Scalar].self, forKey: .at))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .type)
        if !entities.isEmpty { try container.encode(entities, forKey: .entities) }
        if !points.isEmpty { try container.encode(points, forKey: .points) }
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(at, forKey: .at)
    }
}

extension SketchFeature: Codable {
    private enum CodingKeys: String, CodingKey { case plane, entities, constraints, retired }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            plane: try container.decode(SketchPlane.self, forKey: .plane),
            entities: try container.decodeIfPresent([SketchEntity].self, forKey: .entities) ?? [],
            constraints: try container.decodeIfPresent([SketchConstraint].self, forKey: .constraints) ?? [],
            retiredNames: try container.decodeIfPresent([String].self, forKey: .retired) ?? [])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plane, forKey: .plane)
        try container.encode(entities, forKey: .entities)
        try container.encode(constraints, forKey: .constraints)
        if !retiredNames.isEmpty { try container.encode(retiredNames, forKey: .retired) }
    }
}

extension ExtrudeExtent: Codable {
    private enum CodingKeys: String, CodingKey { case type, value, body, face }
    private enum Kind: String, Codable { case distance, symmetric, throughAll, upToFace }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self =
            switch try container.decode(Kind.self, forKey: .type) {
            case .distance: .distance(try container.decode(Scalar.self, forKey: .value))
            case .symmetric: .symmetric(try container.decode(Scalar.self, forKey: .value))
            case .throughAll: .throughAll
            case .upToFace:
                .upToFace(
                    body: try container.decode(String.self, forKey: .body),
                    face: try container.decode(GeometryReference.self, forKey: .face))
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .distance(let value):
            try container.encode(Kind.distance, forKey: .type)
            try container.encode(value, forKey: .value)
        case .symmetric(let value):
            try container.encode(Kind.symmetric, forKey: .type)
            try container.encode(value, forKey: .value)
        case .throughAll:
            try container.encode(Kind.throughAll, forKey: .type)
        case .upToFace(let body, let face):
            try container.encode(Kind.upToFace, forKey: .type)
            try container.encode(body, forKey: .body)
            try container.encode(face, forKey: .face)
        }
    }
}

extension RevolveAxis: Codable {
    private enum CodingKeys: String, CodingKey { case line, global, body, edge }
    private enum Global: String, Codable { case x = "X", y = "Y", z = "Z" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let line = try container.decodeIfPresent(String.self, forKey: .line) {
            self = .sketchLine(line)
        } else if let global = try container.decodeIfPresent(Global.self, forKey: .global) {
            self =
                switch global {
                case .x: .x
                case .y: .y
                case .z: .z
                }
        } else {
            self = .edge(
                body: try container.decode(String.self, forKey: .body),
                edge: try container.decode(GeometryReference.self, forKey: .edge))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sketchLine(let line): try container.encode(line, forKey: .line)
        case .x: try container.encode(Global.x, forKey: .global)
        case .y: try container.encode(Global.y, forKey: .global)
        case .z: try container.encode(Global.z, forKey: .global)
        case .edge(let body, let edge):
            try container.encode(body, forKey: .body)
            try container.encode(edge, forKey: .edge)
        }
    }
}
