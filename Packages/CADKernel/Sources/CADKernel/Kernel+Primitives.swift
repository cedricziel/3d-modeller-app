import OCCTSwift

extension Kernel {
    public static func box(
        width: Double, depth: Double, height: Double, placement: Placement = .identity, feature: String = "Solid"
    ) throws -> Solid {
        try requirePositive(["width": width, "depth": depth, "height": height])
        return try primitive("box", placement, feature, Naming.boxRole) {
            Shape.box(origin: .zero, width: width, height: depth, depth: height)
        }
    }

    public static func cylinder(
        radius: Double, height: Double, placement: Placement = .identity, feature: String = "Solid"
    ) throws -> Solid {
        try requirePositive(["radius": radius, "height": height])
        return try primitive("cylinder", placement, feature, Naming.axialRole) {
            Shape.cylinder(radius: radius, height: height)
        }
    }

    public static func sphere(radius: Double, placement: Placement = .identity, feature: String = "Solid") throws
        -> Solid
    {
        try requirePositive(["radius": radius])
        return try primitive("sphere", placement, feature, { _ in "surface" }) { Shape.sphere(radius: radius) }
    }

    public static func cone(
        bottomRadius: Double, topRadius: Double, height: Double, placement: Placement = .identity,
        feature: String = "Solid"
    ) throws -> Solid {
        try requirePositive(["height": height])
        guard bottomRadius.isFinite, topRadius.isFinite, bottomRadius >= 0, topRadius >= 0 else {
            throw KernelError.invalidDimensions("cone radii must be finite and not negative")
        }
        guard bottomRadius != topRadius else {
            throw KernelError.invalidDimensions("cone radii must differ; use a cylinder for equal radii")
        }
        return try primitive("cone", placement, feature, Naming.axialRole) {
            Shape.cone(bottomRadius: bottomRadius, topRadius: topRadius, height: height)
        }
    }

    public static func torus(
        majorRadius: Double, minorRadius: Double, placement: Placement = .identity, feature: String = "Solid"
    ) throws -> Solid {
        try requirePositive(["majorRadius": majorRadius, "minorRadius": minorRadius])
        guard minorRadius < majorRadius else {
            throw KernelError.invalidDimensions("minorRadius must be smaller than majorRadius")
        }
        return try primitive("torus", placement, feature, { _ in "surface" }) {
            Shape.torus(majorRadius: majorRadius, minorRadius: minorRadius)
        }
    }

    private static func requirePositive(_ values: KeyValuePairs<String, Double>) throws {
        for (name, value) in values where !(value.isFinite && value > 0) {
            throw KernelError.invalidDimensions("\(name) must be a finite number greater than 0")
        }
    }

    private static func primitive(
        _ name: String, _ placement: Placement, _ feature: String, _ role: (Face) -> String, make: () -> Shape?
    ) throws -> Solid {
        try validate(placement)
        return try OCCTSerial.withLock {
            guard let shape = make(), shape.isValid else {
                throw KernelError.operationFailed("create the \(name)")
            }
            let names = Naming.roles(of: shape, feature: feature, role: role)
            return Solid(shape: try placed(shape, placement), faceNames: names)
        }
    }
}
