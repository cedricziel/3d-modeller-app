import Foundation
import Testing
@testable import CADKernel

@Suite("Concurrency")
struct ConcurrencyTests {
    private static func drilledPlate(width: Double) throws -> (volume: Double?, triangles: Int) {
        let plate = try Kernel.box(width: width, depth: 2, height: 2)
        let drill = try Kernel.cylinder(
            radius: 0.5, height: 4, placement: Placement(translation: SIMD3(width / 2, 1, -1)))
        let drilled = try Kernel.boolean(.subtract, plate, drill)
        return (try Kernel.metrics(of: drilled).volume, try Kernel.tessellate(drilled).indices.count / 3)
    }

    @Test("Kernel operations from many tasks at once give the serial results")
    func parallelOperations() async throws {
        let widths = (1...16).map { 1.0 + Double($0) / 4 }
        let results = try await withThrowingTaskGroup(of: (Double, Double?, Int).self) { group in
            for width in widths {
                group.addTask {
                    let result = try Self.drilledPlate(width: width)
                    return (width, result.volume, result.triangles)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(results.count == widths.count)
        for (width, volume, triangles) in results {
            #expect(approx(volume, 4 * width - .pi / 2), "width \(width)")
            #expect(triangles > 0)
        }
    }
}
