@testable import CADAssistantTools
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@MainActor
@Suite("export")
struct ExportToolTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "cadtools-export-\(UUID().uuidString)")

    private func harness(granted: Bool = true) -> Harness {
        let plate = Part(name: "Plate", features: [Fixtures.box("Base", 60, 40, 10), Fixtures.box("Lug", 5, 5, 5)])
        let pin = Part(name: "Pin", features: [Fixtures.box("Rod", 5, 5, 20)])
        let harness = Harness(
            CADDocument(
                parts: [plate, pin],
                assembly: Assembly(instances: [
                    Instance(name: "Base", part: plate.id, grounded: true),
                    Instance(name: "Pin1", part: pin.id, placement: Placement(translation: Vector3(10, 10, 10))),
                ])))
        if granted { harness.session.exportDirectory = folder }
        return harness
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: path).path)
    }

    @Test("export writes an STL of the assembly into the export folder")
    func writesSTL() async throws {
        let harness = harness()

        let result = try await harness.call("export", ["format": "stl", "path": "out/assembly"])
        let contents = try STLReader.read(Data(contentsOf: folder.appending(path: "out/assembly.stl")))

        #expect(result.success, "\(result.message)")
        #expect(result.message.hasPrefix("Wrote out/assembly.stl (STL, "))
        #expect(result.message.contains("products Plate, Pin; occurrences Base, Pin1; 3 bodies, 3 triangles."))
        #expect(contents.triangleCount == 3)
        #expect(harness.commits.isEmpty)
    }

    @Test("export writes a 3MF of one part, named after it by default")
    func writes3MF() async throws {
        let harness = harness()

        let result = try await harness.call("export", ["format": "3mf", "part": "Plate", "tolerance": 0.1])
        let contents = try ThreeMFReader.read(Data(contentsOf: folder.appending(path: "Plate.3mf")))

        #expect(result.success, "\(result.message)")
        #expect(contents.items.count == 1)
        #expect(contents.objectNames.contains("Plate"))
    }

    @Test("export names a body's file after its part and body")
    func bodyDefaultName() async throws {
        let result = try await harness().call("export", ["format": "stl", "part": "Plate", "body": "Body2"])

        #expect(result.success, "\(result.message)")
        #expect(exists("Plate-Body2.stl"))
    }

    @Test("export refuses an extension of another format")
    func wrongExtensionRefused() async throws {
        let result = try await harness().call("export", ["format": "stl", "path": "a.3mf"])

        #expect(result.message == "'a.3mf' names a 3MF file, but the format is STL.")
    }

    @Test("export refuses paths that leave the export folder")
    func pathEscapesRefused() async throws {
        let harness = harness()

        for path in ["../a.stl", "/tmp/a.stl", "~/a.stl", "x/../../a.stl"] {
            let result = try await harness.call("export", ["format": "stl", "path": .string(path)])
            #expect(!result.success, "\(path)")
        }
        #expect(
            !FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().appending(path: "a.stl").path))
    }

    @Test("export refuses a subfolder that links outside the export folder")
    func symlinkEscapeRefused() async throws {
        let harness = harness()
        let outside = FileManager.default.temporaryDirectory.appending(path: "cadtools-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "link"), withDestinationURL: outside)

        let result = try await harness.call("export", ["format": "stl", "path": "link/a.stl"])

        #expect(result.message == "'link/a.stl' leads outside the export folder through link.")
        #expect(!FileManager.default.fileExists(atPath: outside.appending(path: "a.stl").path))
    }

    @Test("export replaces an existing file only when asked")
    func existingFileRefused() async throws {
        let harness = harness()
        _ = try await harness.call("export", ["format": "stl"])

        let again = try await harness.call("export", ["format": "stl"])
        let replaced = try await harness.call("export", ["format": "stl", "overwrite": true])

        #expect(again.message == "model.stl already exists; pass overwrite: true to replace it.")
        #expect(replaced.success)
    }

    @Test("export refuses without an export folder")
    func noDirectoryRefused() async throws {
        let result = try await harness(granted: false).call("export", ["format": "stl"])

        #expect(result.message == "This host grants no export folder, so export cannot write files here.")
    }

    @Test("export refuses unclear or unknown targets")
    func targetRefusals() async throws {
        let harness = harness()

        #expect(
            try await harness.call("export", ["format": "stl", "part": "Nope"]).message.hasPrefix(
                "No part named 'Nope'"))
        #expect(
            try await harness.call("export", ["format": "stl", "part": "Plate", "instance": "Base"]).message
                == "Give either instance or part (with body), not both.")
        #expect(
            try await harness.call("export", ["format": "stl", "body": "Body1"]).message
                .hasPrefix("The document has several parts"))
        #expect(
            try await harness.call("export", ["format": "stl", "part": "Pin", "body": "Body7"]).message
                == "Pin has no body named Body7; bodies: Body1")
        #expect(
            try await harness.call("export", ["format": "obj"]).message == "'format' is step, stl or 3mf, not 'obj'.")
    }

    @Test("export checks the tolerance")
    func toleranceRange() async throws {
        let harness = harness()
        let tooFine = try await harness.call("export", ["format": "stl", "tolerance": 0.0001])
        let onStep = try await harness.call("export", ["format": "step", "tolerance": 0.1])

        #expect(tooFine.message == "'tolerance' is a number of mm from 0.001 to 1.")
        #expect(onStep.message == "'tolerance' applies to stl and 3mf only; STEP is exact.")
    }
}
