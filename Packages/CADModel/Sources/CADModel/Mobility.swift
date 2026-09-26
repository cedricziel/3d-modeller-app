import simd

/// A joint as the solver held it: its effective kind and its frames in assembly coordinates.
struct MobilityJoint {
    var kind: JointKind
    var bodyA: Int
    var bodyB: Int
    var a: RigidTransform
    var b: RigidTransform
}

/// How far each body can still move, from the rank of the joints' constraints linearised at the current pose.
/// Counting constraints instead would miss redundant ones, such as those of a closed planar linkage.
enum Mobility {
    /// Each body's remaining freedoms, 0…6; grounded bodies have none.
    static func freedoms(bodies: Int, grounded: Set<Int>, joints: [MobilityJoint]) -> [Int] {
        let moving = (0..<bodies).filter { !grounded.contains($0) }
        let column = Dictionary(uniqueKeysWithValues: moving.enumerated().map { ($1, $0 * 6) })
        let width = moving.count * 6
        guard width > 0 else { return Array(repeating: 0, count: bodies) }
        let length = max(1, joints.map { simd_length($0.b.translation) }.max() ?? 1)
        var rows: [[Double]] = []
        for joint in joints {
            let axes = [joint.a.rotation.columns.0, joint.a.rotation.columns.1, joint.a.rotation.columns.2]
            let (turns, moves) = constrained(joint.kind)
            let point = joint.b.translation
            func row(rotation: SIMD3<Double>, translation: SIMD3<Double>) -> [Double] {
                var row = [Double](repeating: 0, count: width)
                for (body, sign) in [(joint.bodyB, 1.0), (joint.bodyA, -1.0)] {
                    guard let start = column[body] else { continue }
                    for axis in 0..<3 {
                        row[start + axis] += sign * rotation[axis] / length
                        row[start + 3 + axis] += sign * translation[axis]
                    }
                }
                return row
            }
            rows += turns.map { row(rotation: axes[$0], translation: .zero) }
            rows += moves.map { row(rotation: simd_cross(point, axes[$0]), translation: axes[$0]) }
        }
        let basis = nullSpace(rows, width: width)
        var freedoms = Array(repeating: 0, count: bodies)
        for body in moving {
            let start = column[body]!
            let block = basis.map { Array($0[start..<start + 6]) }
            freedoms[body] = rank(block, tolerance: 1e-8)
        }
        return freedoms
    }

    /// The axes of frame a about which relative turning, and along which relative motion of b's origin, is held.
    private static func constrained(_ kind: JointKind) -> (turns: [Int], moves: [Int]) {
        switch kind {
        case .fixed: ([0, 1, 2], [0, 1, 2])
        case .revolute: ([0, 1], [0, 1, 2])
        case .slider: ([0, 1, 2], [0, 1])
        case .cylindrical: ([0, 1], [0, 1])
        case .ball: ([], [0, 1, 2])
        case .planar: ([0, 1], [2])
        }
    }

    /// A basis of the vectors every row is orthogonal to, one vector per free column of the reduced echelon form.
    private static func nullSpace(_ rows: [[Double]], width: Int) -> [[Double]] {
        var matrix = rows
        let largest = rows.flatMap { $0 }.map(abs).max() ?? 0
        let tolerance = 1e-9 * max(largest, 1e-300)
        var pivots: [(row: Int, column: Int)] = []
        var row = 0
        for column in 0..<width where row < matrix.count {
            guard let best = (row..<matrix.count).max(by: { abs(matrix[$0][column]) < abs(matrix[$1][column]) }),
                abs(matrix[best][column]) > tolerance
            else { continue }
            matrix.swapAt(row, best)
            let pivot = matrix[row][column]
            matrix[row] = matrix[row].map { $0 / pivot }
            for other in matrix.indices where other != row && matrix[other][column] != 0 {
                let factor = matrix[other][column]
                for index in 0..<width {
                    matrix[other][index] -= factor * matrix[row][index]
                }
            }
            pivots.append((row, column))
            row += 1
        }
        let pivotColumns = Set(pivots.map(\.column))
        return (0..<width).filter { !pivotColumns.contains($0) }.map { free in
            var vector = [Double](repeating: 0, count: width)
            vector[free] = 1
            for pivot in pivots {
                vector[pivot.column] = -matrix[pivot.row][free]
            }
            return vector
        }
    }

    private static func rank(_ rows: [[Double]], tolerance: Double) -> Int {
        guard let width = rows.first?.count else { return 0 }
        var matrix = rows
        var rank = 0
        for column in 0..<width where rank < matrix.count {
            guard let best = (rank..<matrix.count).max(by: { abs(matrix[$0][column]) < abs(matrix[$1][column]) }),
                abs(matrix[best][column]) > tolerance
            else { continue }
            matrix.swapAt(rank, best)
            for other in (rank + 1)..<matrix.count {
                let factor = matrix[other][column] / matrix[rank][column]
                for index in column..<width {
                    matrix[other][index] -= factor * matrix[rank][index]
                }
            }
            rank += 1
        }
        return rank
    }
}
