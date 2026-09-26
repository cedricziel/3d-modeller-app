extension FeatureKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, width, depth, height, radius, bottomRadius, topRadius, majorRadius, minorRadius
        case placement, operation, target, tools, body, edges, faces, distance, thickness
    }

    private enum KindName: String, Codable {
        case box, cylinder, sphere, cone, torus, boolean, transform, fillet, chamfer, shell
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func scalar(_ key: CodingKeys) throws -> Scalar { try container.decode(Scalar.self, forKey: key) }
        let shape: PrimitiveShape
        switch try container.decode(KindName.self, forKey: .type) {
        case .boolean:
            self = .boolean(
                BooleanFeature(
                    operation: try container.decode(BooleanOperation.self, forKey: .operation),
                    target: try container.decode(String.self, forKey: .target),
                    tools: try container.decode([String].self, forKey: .tools)
                ))
            return
        case .transform:
            self = .transform(
                TransformFeature(
                    body: try container.decode(String.self, forKey: .body),
                    placement: try container.decodeIfPresent(Placement.self, forKey: .placement) ?? .identity
                ))
            return
        case .fillet:
            self = .fillet(
                FilletFeature(
                    body: try container.decode(String.self, forKey: .body),
                    edges: try container.decode([GeometryReference].self, forKey: .edges), radius: try scalar(.radius)))
            return
        case .chamfer:
            self = .chamfer(
                ChamferFeature(
                    body: try container.decode(String.self, forKey: .body),
                    edges: try container.decode([GeometryReference].self, forKey: .edges),
                    distance: try scalar(.distance)))
            return
        case .shell:
            self = .shell(
                ShellFeature(
                    body: try container.decode(String.self, forKey: .body),
                    faces: try container.decode([GeometryReference].self, forKey: .faces),
                    thickness: try scalar(.thickness)))
            return
        case .box:
            shape = .box(width: try scalar(.width), depth: try scalar(.depth), height: try scalar(.height))
        case .cylinder:
            shape = .cylinder(radius: try scalar(.radius), height: try scalar(.height))
        case .sphere:
            shape = .sphere(radius: try scalar(.radius))
        case .cone:
            shape = .cone(
                bottomRadius: try scalar(.bottomRadius), topRadius: try scalar(.topRadius), height: try scalar(.height))
        case .torus:
            shape = .torus(majorRadius: try scalar(.majorRadius), minorRadius: try scalar(.minorRadius))
        }
        self = .primitive(
            PrimitiveFeature(
                shape,
                placement: try container.decodeIfPresent(Placement.self, forKey: .placement) ?? .identity,
                operation: try container.decodeIfPresent(SolidOperation.self, forKey: .operation) ?? .newBody
            ))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .boolean(let boolean):
            try container.encode(KindName.boolean, forKey: .type)
            try container.encode(boolean.operation, forKey: .operation)
            try container.encode(boolean.target, forKey: .target)
            try container.encode(boolean.tools, forKey: .tools)
        case .transform(let transform):
            try container.encode(KindName.transform, forKey: .type)
            try container.encode(transform.body, forKey: .body)
            try container.encode(transform.placement, forKey: .placement)
        case .fillet(let fillet):
            try container.encode(KindName.fillet, forKey: .type)
            try container.encode(fillet.body, forKey: .body)
            try container.encode(fillet.edges, forKey: .edges)
            try container.encode(fillet.radius, forKey: .radius)
        case .chamfer(let chamfer):
            try container.encode(KindName.chamfer, forKey: .type)
            try container.encode(chamfer.body, forKey: .body)
            try container.encode(chamfer.edges, forKey: .edges)
            try container.encode(chamfer.distance, forKey: .distance)
        case .shell(let shell):
            try container.encode(KindName.shell, forKey: .type)
            try container.encode(shell.body, forKey: .body)
            try container.encode(shell.faces, forKey: .faces)
            try container.encode(shell.thickness, forKey: .thickness)
        case .primitive(let primitive):
            try container.encode(primitive.placement, forKey: .placement)
            try container.encode(primitive.operation, forKey: .operation)
            switch primitive.shape {
            case .box(let width, let depth, let height):
                try container.encode(KindName.box, forKey: .type)
                try container.encode(width, forKey: .width)
                try container.encode(depth, forKey: .depth)
                try container.encode(height, forKey: .height)
            case .cylinder(let radius, let height):
                try container.encode(KindName.cylinder, forKey: .type)
                try container.encode(radius, forKey: .radius)
                try container.encode(height, forKey: .height)
            case .sphere(let radius):
                try container.encode(KindName.sphere, forKey: .type)
                try container.encode(radius, forKey: .radius)
            case .cone(let bottomRadius, let topRadius, let height):
                try container.encode(KindName.cone, forKey: .type)
                try container.encode(bottomRadius, forKey: .bottomRadius)
                try container.encode(topRadius, forKey: .topRadius)
                try container.encode(height, forKey: .height)
            case .torus(let majorRadius, let minorRadius):
                try container.encode(KindName.torus, forKey: .type)
                try container.encode(majorRadius, forKey: .majorRadius)
                try container.encode(minorRadius, forKey: .minorRadius)
            }
        }
    }
}

extension SolidOperation: Codable {
    private enum CodingKeys: String, CodingKey { case mode, body }
    private enum Mode: String, Codable { case newBody, join, cut, intersect }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(Mode.self, forKey: .mode)
        if mode == .newBody {
            self = .newBody
            return
        }
        let body = try container.decode(String.self, forKey: .body)
        self =
            switch mode {
            case .newBody: .newBody
            case .join: .join(body)
            case .cut: .cut(body)
            case .intersect: .intersect(body)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let mode: Mode =
            switch self {
            case .newBody: .newBody
            case .join: .join
            case .cut: .cut
            case .intersect: .intersect
            }
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(targetBody, forKey: .body)
    }
}
