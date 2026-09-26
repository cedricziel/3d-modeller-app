public struct Vector3: Codable, Sendable, Hashable {
    public var x: Scalar
    public var y: Scalar
    public var z: Scalar

    public init(_ x: Scalar = 0, _ y: Scalar = 0, _ z: Scalar = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Scalar.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Scalar.self, forKey: .y) ?? 0
        z = try container.decodeIfPresent(Scalar.self, forKey: .z) ?? 0
    }
}

public struct Placement: Codable, Sendable, Hashable {
    public var translation: Vector3
    public var rotationAxis: Vector3
    public var rotationDegrees: Scalar

    public static let identity = Placement()

    public init(translation: Vector3 = Vector3(), rotationAxis: Vector3 = Vector3(0, 0, 1), rotationDegrees: Scalar = 0)
    {
        self.translation = translation
        self.rotationAxis = rotationAxis
        self.rotationDegrees = rotationDegrees
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translation = try container.decodeIfPresent(Vector3.self, forKey: .translation) ?? Vector3()
        rotationAxis = try container.decodeIfPresent(Vector3.self, forKey: .rotationAxis) ?? Vector3(0, 0, 1)
        rotationDegrees = try container.decodeIfPresent(Scalar.self, forKey: .rotationDegrees) ?? 0
    }
}

public struct ResolvedPlacement: Sendable, Hashable {
    public var translation: SIMD3<Double>
    public var rotationAxis: SIMD3<Double>
    public var rotationDegrees: Double

    public init(
        translation: SIMD3<Double> = .zero, rotationAxis: SIMD3<Double> = SIMD3(0, 0, 1), rotationDegrees: Double = 0
    ) {
        self.translation = translation
        self.rotationAxis = rotationAxis
        self.rotationDegrees = rotationDegrees
    }
}
