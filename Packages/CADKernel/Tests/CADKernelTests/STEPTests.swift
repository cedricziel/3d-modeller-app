import Foundation
import Testing
import simd
@testable import CADKernel

@Suite("STEP files")
struct STEPTests {
    private let red = SIMD3<Double>(0.85, 0.27, 0.27)

    private func temporaryFile(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cadkernel-step-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    private func volume(_ solids: [Solid]) throws -> Double {
        try solids.reduce(0) { $0 + (try Kernel.metrics(of: $1).volume ?? 0) }
    }

    @Test("A single product reads back as one solid in millimetres")
    func singleProduct() throws {
        let url = try temporaryFile("block.step")
        let block = try Kernel.box(width: 10, depth: 20, height: 30)
        try Kernel.writeSTEP(
            products: [STEPProduct(name: "Block", bodies: [("Body1", block)], color: red)], occurrences: [],
            name: "Assembly", to: url)

        let contents = try Kernel.readSTEP(from: url)
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(contents.solids.count == 1)
        #expect(approx(try volume(contents.solids), 6000))
        #expect(contents.names.contains("Block"))
        #expect(text.contains("SI_UNIT(.MILLI.,.METRE.)"))
        #expect(text.contains("AUTOMOTIVE_DESIGN"))
    }

    @Test("Two occurrences share one product and keep their placements")
    func sharedProductTwoOccurrences() throws {
        let url = try temporaryFile("pair.step")
        let block = try Kernel.box(width: 10, depth: 20, height: 30)
        let turn = simd_double3x3(simd_quatd(angle: .pi / 2, axis: SIMD3(0, 0, 1)))
        try Kernel.writeSTEP(
            products: [STEPProduct(name: "Block", bodies: [("Body1", block)], color: red)],
            occurrences: [
                STEPOccurrence(name: "A", product: 0, rotation: matrix_identity_double3x3, translation: .zero),
                STEPOccurrence(name: "B", product: 0, rotation: turn, translation: SIMD3(100, 0, 0)),
            ],
            name: "Assembly", to: url)

        let contents = try Kernel.readSTEP(from: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        let bounds = try contents.solids.map { try Kernel.metrics(of: $0) }
        let turned = bounds.first { $0.boundsMin.x > 50 }

        #expect(contents.solids.count == 2)
        #expect(approx(try volume(contents.solids), 12000))
        #expect(text.components(separatedBy: "MANIFOLD_SOLID_BREP").count - 1 == 1)
        #expect(approx(turned?.boundsMin ?? .zero, SIMD3(80, 0, 0), tolerance: 1e-6))
        #expect(approx(turned?.boundsMax ?? .zero, SIMD3(100, 10, 30), tolerance: 1e-6))
        #expect(contents.names.contains("A"))
        #expect(contents.names.contains("B"))
        #expect(contents.names.contains("Assembly"))
    }

    @Test("A product with several bodies names each body")
    func multiBodyProduct() throws {
        let url = try temporaryFile("multi.step")
        let first = try Kernel.box(width: 10, depth: 10, height: 10)
        let second = try Kernel.box(
            width: 5, depth: 5, height: 5, placement: Placement(translation: SIMD3(20, 0, 0)))
        try Kernel.writeSTEP(
            products: [STEPProduct(name: "Plate", bodies: [("Body1", first), ("Body2", second)], color: red)],
            occurrences: [], name: "Assembly", to: url)

        let contents = try Kernel.readSTEP(from: url)

        #expect(contents.solids.count == 2)
        #expect(approx(try volume(contents.solids), 1125))
        #expect(contents.names.contains("Plate"))
        #expect(contents.names.contains("Body1"))
        #expect(contents.names.contains("Body2"))
    }

    @Test("A product's colour survives the round trip")
    func colourRoundTrips() throws {
        let url = try temporaryFile("colour.step")
        try Kernel.writeSTEP(
            products: [
                STEPProduct(
                    name: "Block", bodies: [("Body1", try Kernel.box(width: 1, depth: 1, height: 1))], color: red)
            ],
            occurrences: [], name: "Assembly", to: url)

        let colors = try Kernel.readSTEP(from: url).colors

        #expect(colors.contains { simd_distance($0, red) < 1e-3 })
    }

    @Test("An occurrence's own colour survives the round trip on that occurrence")
    func occurrenceColourRoundTrips() throws {
        let url = try temporaryFile("occurrence-colour.step")
        let green = SIMD3<Double>(0.18, 0.49, 0.2)
        let block = try Kernel.box(width: 1, depth: 1, height: 1)
        try Kernel.writeSTEP(
            products: [STEPProduct(name: "Block", bodies: [("Body1", block)], color: green)],
            occurrences: [
                STEPOccurrence(name: "Plain", product: 0, rotation: matrix_identity_double3x3, translation: .zero),
                STEPOccurrence(
                    name: "Red", product: 0, rotation: matrix_identity_double3x3, translation: SIMD3(5, 0, 0),
                    color: red),
            ],
            name: "Assembly", to: url)

        let named = try Kernel.readSTEP(from: url).namedColors

        #expect(named["Plain"].map { simd_distance($0, green) < 1e-3 } == true)
        #expect(named["Red"].map { simd_distance($0, red) < 1e-3 } == true)
    }

    @Test("Writing into a missing folder is an error")
    func badPathThrows() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)/a.step")
        let block = try Kernel.box(width: 1, depth: 1, height: 1)

        #expect(throws: KernelError.self) {
            try Kernel.writeSTEP(
                products: [STEPProduct(name: "Block", bodies: [("Body1", block)], color: red)], occurrences: [],
                name: "Assembly", to: url)
        }
    }

    @Test("Reading a file that is not STEP is an error")
    func notStepThrows() throws {
        let url = try temporaryFile("junk.step")
        try Data("not a step file".utf8).write(to: url)

        #expect(throws: KernelError.self) { try Kernel.readSTEP(from: url) }
    }
}
