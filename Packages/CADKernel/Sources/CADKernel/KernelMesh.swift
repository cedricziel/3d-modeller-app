import simd

public struct KernelMesh: Sendable, Equatable {
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let indices: [UInt32]
}

extension KernelMesh {
    init(positions: [SIMD3<Float>], indices: [UInt32]) {
        var sums = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for start in stride(from: 0, to: indices.count, by: 3) {
            let (i0, i1, i2) = (Int(indices[start]), Int(indices[start + 1]), Int(indices[start + 2]))
            let areaWeighted = simd_cross(positions[i1] - positions[i0], positions[i2] - positions[i0])
            sums[i0] += areaWeighted
            sums[i1] += areaWeighted
            sums[i2] += areaWeighted
        }
        self.init(
            positions: positions,
            normals: sums.map { simd_length($0) > 0 ? simd_normalize($0) : SIMD3(0, 0, 1) },
            indices: indices
        )
    }
}
