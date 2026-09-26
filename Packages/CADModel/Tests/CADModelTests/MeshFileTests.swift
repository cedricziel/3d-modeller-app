@testable import CADModel
import Foundation
import Testing
import simd

@Suite("Mesh files")
struct MeshFileTests {
    private let triangle = BodyMesh(
        positions: [.zero, SIMD3(2, 0, 0), SIMD3(0, 3, 0)], normals: [], indices: [0, 1, 2])

    private func temporaryFile(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cadmodel-mesh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    @Test("Binary STL has a header, a count and 50 bytes per triangle")
    func binaryLayout() throws {
        let moved = triangle.transformed(
            by: RigidTransform(rotation: matrix_identity_double3x3, translation: SIMD3(0, 0, 5)))
        let data = STLWriter.data([triangle, moved])
        let contents = try STLReader.read(data)
        let expectedSize = 80 + 4 + 2 * 50

        #expect(data.count == expectedSize)
        #expect(contents.triangleCount == 2)
        #expect(contents.bounds == Bounds(min: .zero, max: SIMD3(2, 3, 5)))
        #expect(contents.normals.allSatisfy { abs(simd_length($0) - 1) < 1e-6 })
        #expect(contents.normals.first == SIMD3(0, 0, 1))
    }

    @Test("A truncated STL is an error")
    func truncatedSTL() {
        let data = STLWriter.data([triangle]).prefix(100)

        #expect(throws: ExportError.self) { try STLReader.read(Data(data)) }
    }

    @Test("CRC-32 matches the standard check value")
    func crc() {
        #expect(ZipArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test("The zip opens with unzip and reads back")
    func zipOpens() throws {
        var archive = ZipArchive()
        archive.add("a.txt", Data("hello".utf8))
        archive.add("dir/b.txt", Data("world".utf8))
        let url = try temporaryFile("test.zip")
        try archive.data().write(to: url)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-tq", url.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let entries = try ZipArchive.entries(of: archive.data())

        #expect(process.terminationStatus == 0)
        #expect(entries["a.txt"] == Data("hello".utf8))
        #expect(entries["dir/b.txt"] == Data("world".utf8))
    }

    @Test("3MF places each occurrence with its transform, in millimetres")
    func threeMF() throws {
        let turn = simd_double3x3(SIMD3(0, 1, 0), SIMD3(-1, 0, 0), SIMD3(0, 0, 1))
        let scene = ExportScene(
            name: "Assembly",
            products: [ExportProduct(name: "A & B", bodies: [("Body1", triangle)], color: ExportPalette.color(0))],
            occurrences: [
                ExportOccurrence(name: "One", product: 0, transform: .identity),
                ExportOccurrence(
                    name: "Two", product: 0, transform: RigidTransform(rotation: turn, translation: SIMD3(10, 0, 0))),
            ])
        let data = ThreeMFWriter.data(scene)
        let contents = try ThreeMFReader.read(data)
        let expectedMin = SIMD3<Double>(7, 0, 0)
        let expectedMax = SIMD3<Double>(10, 2, 0)
        let second = try #require(contents.items.last)

        #expect(contents.unit == "millimeter")
        #expect(contents.objectNames.contains("A & B"))
        #expect(contents.items.count == 2)
        #expect(contents.triangleCount == 2)
        #expect(simd_distance(second.bounds.min, expectedMin) < 1e-6)
        #expect(simd_distance(second.bounds.max, expectedMax) < 1e-6)
        #expect(contents.colors == ["#457AD9"])
        let model = String(decoding: try #require(try ZipArchive.entries(of: data)["3D/3dmodel.model"]), as: UTF8.self)
        #expect(model.contains("transform=\"0.0 1.0 0.0 -1.0 0.0 0.0 0.0 0.0 1.0 10.0 0.0 0.0\""))
    }

    @Test("3MF merges the corners the kernel repeats along shared edges, so the mesh is closed")
    func threeMFWelds() throws {
        let square = BodyMesh(
            positions: [.zero, SIMD3(1, 0, 0), SIMD3(1, 1, 0), .zero, SIMD3(1, 1, 0), SIMD3(0, 1, 0)], normals: [],
            indices: [0, 1, 2, 3, 4, 5])

        let (positions, triangles) = ThreeMFWriter.welded(square)

        #expect(positions.count == 4)
        #expect(triangles.count == 2)
    }

    @Test("3MF names keep only characters XML allows")
    func controlCharacters() {
        #expect(ThreeMFWriter.escape("A\u{1}<B>") == "A&lt;B&gt;")
    }

    @Test("3MF with several bodies in a product groups them under one object")
    func threeMFComponents() throws {
        let scene = ExportScene(
            name: "Plate",
            products: [
                ExportProduct(name: "Plate", bodies: [("Body1", triangle), ("Body2", triangle)], color: SIMD3(1, 0, 0))
            ],
            occurrences: [])
        let contents = try ThreeMFReader.read(ThreeMFWriter.data(scene))

        #expect(contents.items.count == 1)
        #expect(contents.triangleCount == 2)
        #expect(contents.objectNames.contains("Plate"))
        #expect(contents.objectNames.contains("Body2"))
    }
}
