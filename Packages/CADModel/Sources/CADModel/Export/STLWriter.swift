import Foundation
import simd

/// Binary STL: an 80-byte header, the triangle count, then per triangle its normal, three corners and two spare
/// bytes, all little-endian. Lengths are millimetres.
public enum STLWriter {
    public static func data(_ meshes: [BodyMesh]) -> Data {
        var data = Data("3D Modeller binary STL, millimetres".utf8)
        data.append(Data(count: 80 - data.count))
        data.appendLittleEndian(UInt32(meshes.reduce(0) { $0 + $1.triangleCount }))
        for mesh in meshes {
            for start in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                let corners = (0..<3).map { mesh.positions[Int(mesh.indices[start + $0])] }
                let cross = simd_cross(corners[1] - corners[0], corners[2] - corners[0])
                let normal = simd_length(cross) > 0 ? simd_normalize(cross) : .zero
                for vector in [normal] + corners {
                    data.appendLittleEndian(vector.x.bitPattern)
                    data.appendLittleEndian(vector.y.bitPattern)
                    data.appendLittleEndian(vector.z.bitPattern)
                }
                data.appendLittleEndian(UInt16(0))
            }
        }
        return data
    }
}

public struct STLContents: Sendable, Equatable {
    public let triangleCount: Int
    public let normals: [SIMD3<Float>]
    /// Nil when the file has no triangles.
    public let bounds: Bounds?
}

/// Reads back binary STL, for checking exports.
public enum STLReader {
    public static func read(_ data: Data) throws(ExportError) -> STLContents {
        let bytes = [UInt8](data)
        guard bytes.count >= 84 else { throw ExportError("The STL file is shorter than its header") }
        let count = Int(bytes.littleEndianUInt32(at: 80))
        guard bytes.count == 84 + count * 50 else {
            throw ExportError("The STL file has \(bytes.count) bytes; \(count) triangles need \(84 + count * 50)")
        }
        var normals: [SIMD3<Float>] = []
        var low = SIMD3<Double>(repeating: .infinity)
        var high = SIMD3<Double>(repeating: -.infinity)
        for triangle in 0..<count {
            let start = 84 + triangle * 50
            func vector(_ index: Int) -> SIMD3<Float> {
                let offset = start + index * 12
                return SIMD3(
                    Float(bitPattern: bytes.littleEndianUInt32(at: offset)),
                    Float(bitPattern: bytes.littleEndianUInt32(at: offset + 4)),
                    Float(bitPattern: bytes.littleEndianUInt32(at: offset + 8)))
            }
            normals.append(vector(0))
            for corner in 1...3 {
                let point = SIMD3<Double>(vector(corner))
                low = simd_min(low, point)
                high = simd_max(high, point)
            }
        }
        return STLContents(
            triangleCount: count, normals: normals, bounds: count > 0 ? Bounds(min: low, max: high) : nil)
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

extension [UInt8] {
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(self[offset + $1]) << (8 * $1) }
    }

    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }
}
