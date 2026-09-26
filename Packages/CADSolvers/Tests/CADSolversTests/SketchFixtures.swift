@testable import CADSolvers

enum Fixtures {
    /// Four lines bottom, right, top, left from the given corners (counter-clockwise from the
    /// bottom-left), each line's endpoints taken from `ends` when given.
    static func rectangle(
        _ ends: [(SketchPoint, SketchPoint)],
        fixed: Bool = true,
        dimensions: Bool = true,
        width: Double = 60,
        height: Double = 40
    ) -> Sketch {
        var constraints: [SketchConstraint] = [
            .coincident(.end(0), .start(1)),
            .coincident(.end(1), .start(2)),
            .coincident(.end(2), .start(3)),
            .coincident(.end(3), .start(0)),
            .horizontal(0),
            .horizontal(2),
            .vertical(1),
            .vertical(3),
        ]
        if fixed { constraints.append(.fixed(.start(0))) }
        if dimensions {
            constraints.append(.distance(.start(0), .end(0), width))
            constraints.append(.distance(.start(1), .end(1), height))
        }
        return Sketch(
            entities: ends.map { SketchEntity(.line(start: $0.0, end: $0.1)) },
            constraints: constraints
        )
    }

    static let exactRectangle = rectangle([
        (SketchPoint(0, 0), SketchPoint(60, 0)),
        (SketchPoint(60, 0), SketchPoint(60, 40)),
        (SketchPoint(60, 40), SketchPoint(0, 40)),
        (SketchPoint(0, 40), SketchPoint(0, 0)),
    ])

    static let sloppyEnds: [(SketchPoint, SketchPoint)] = [
        (SketchPoint(0, 0), SketchPoint(55, 4)),
        (SketchPoint(57, -2), SketchPoint(67, 35)),
        (SketchPoint(64, 38), SketchPoint(-5, 47)),
        (SketchPoint(-3, 44), SketchPoint(2, -6)),
    ]
}

func close(_ a: Double, _ b: Double, tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

func close(_ a: SketchPoint, _ b: SketchPoint, tolerance: Double = 1e-6) -> Bool {
    close(a.x, b.x, tolerance: tolerance) && close(a.y, b.y, tolerance: tolerance)
}

extension SketchSolution {
    func line(_ index: Int) -> (start: SketchPoint, end: SketchPoint)? {
        guard case .line(let start, let end) = entities[index].geometry else { return nil }
        return (start, end)
    }

    func point(_ index: Int) -> SketchPoint? {
        guard case .point(let point) = entities[index].geometry else { return nil }
        return point
    }

    func circle(_ index: Int) -> (center: SketchPoint, radius: Double)? {
        switch entities[index].geometry {
        case .circle(let center, let radius), .arc(let center, let radius, _, _): (center, radius)
        default: nil
        }
    }

    func arcAngles(_ index: Int) -> (start: Double, end: Double)? {
        guard case .arc(_, _, let start, let end) = entities[index].geometry else { return nil }
        return (start, end)
    }
}

/// The angle brought into [-π, π).
func normalized(_ angle: Double) -> Double {
    var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if value >= .pi { value -= 2 * .pi }
    if value < -.pi { value += 2 * .pi }
    return value
}
