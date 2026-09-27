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

        let messages: [String: String] = [
            "../a.stl": "'../a.stl' leaves the export folder; '..' is not allowed.",
            "x/../../a.stl": "'x/../../a.stl' leaves the export folder; '..' is not allowed.",
            "/tmp/cadtools-a.stl":
                "'/tmp/cadtools-a.stl' is not relative; give a path inside the export folder, e.g. \"part.stl\".",
            "~/cadtools-a.stl":
                "'~/cadtools-a.stl' is not relative; give a path inside the export folder, e.g. \"part.stl\".",
        ]
        for (path, message) in messages {
            let result = try await harness.call("export", ["format": "stl", "path": .string(path)])
            #expect(result.message == message, "\(path)")
        }
        #expect(!FileManager.default.fileExists(atPath: "/tmp/cadtools-a.stl"))
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

        let before = try Data(contentsOf: folder.appending(path: "model.stl"))
        _ = try await harness.call("delete_instance", ["instance": "Pin1"])
        let smaller = try await harness.call("export", ["format": "stl", "overwrite": true])
        let after = try Data(contentsOf: folder.appending(path: "model.stl"))

        #expect(again.message == "model.stl already exists; pass overwrite: true to replace it.")
        #expect(replaced.success)
        #expect(smaller.success, "\(smaller.message)")
        #expect(after.count < before.count)
    }

    @Test("export refuses a file name that is only an extension or starts with a dot")
    func dotNameRefused() async throws {
        let harness = harness()

        let bare = try await harness.call("export", ["format": "step", "path": ".step"])
        let nested = try await harness.call("export", ["format": "stl", "path": "out/.hidden"])

        #expect(bare.message == "'.step' starts with a dot; give a visible file name, e.g. \"part.step\".")
        #expect(nested.message == "'out/.hidden' starts with a dot; give a visible file name, e.g. \"part.stl\".")
        #expect(!exists(".step.step"))
        #expect(!exists("out"))
    }

    @Test("export refuses a subfolder that is a dangling link or a file")
    func brokenSubfolderRefused() async throws {
        let harness = harness()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: folder.appending(path: "gone").path, withDestinationPath: folder.appending(path: "nowhere").path)
        try Data("x".utf8).write(to: folder.appending(path: "notes"))

        let dangling = try await harness.call("export", ["format": "stl", "path": "gone/a.stl"])
        let file = try await harness.call("export", ["format": "stl", "path": "notes/a.stl"])

        #expect(dangling.message == "'gone/a.stl' goes through gone, a symbolic link to nothing.")
        #expect(file.message == "'notes/a.stl' goes through notes, which is a file, not a folder.")
        #expect(!exists("nowhere"))
    }

    @Test("A failed export creates no folders")
    func failedExportLeavesNoFolders() async throws {
        let harness = Harness(CADDocument(parts: [Part(name: "Empty")]))
        harness.session.exportDirectory = folder

        let result = try await harness.call("export", ["format": "stl", "path": "new/deeper/a.stl"])

        #expect(!result.success)
        #expect(result.message.hasPrefix("Nothing to export"), "\(result.message)")
        #expect(!exists("new"))
    }

    @Test("A file planted after the check is not replaced")
    func plantedFileKept() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = try ExportPath.resolve("race", in: folder, format: .stl, overwrite: false)
        try Data("theirs".utf8).write(to: destination.url)

        let error = await Self.failure(of: destination)
        #expect(error == ExportError("race.stl already exists; pass overwrite: true to replace it."))
        #expect(try String(contentsOf: destination.url, encoding: .utf8) == "theirs")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["race.stl"])
    }

    @Test("A symbolic link planted after the check is replaced, not followed")
    func plantedLinkNotFollowed() async throws {
        let outside = FileManager.default.temporaryDirectory.appending(path: "cadtools-target-\(UUID().uuidString)")
        try Data("theirs".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = try ExportPath.resolve("race.stl", in: folder, format: .stl, overwrite: true)
        try FileManager.default.createSymbolicLink(at: destination.url, withDestinationURL: outside)

        try await destination.write { (url) throws(ExportError) in try Self.writeOurs(to: url) }

        let kind = try FileManager.default.attributesOfItem(atPath: destination.url.path)[.type] as? FileAttributeType
        #expect(kind == .typeRegular)
        #expect(try String(contentsOf: destination.url, encoding: .utf8) == "ours")
        #expect(try String(contentsOf: outside, encoding: .utf8) == "theirs")
    }

    @Test("A subfolder swapped for a link after the check is not written through")
    func swappedFolderRefused() async throws {
        let outside = FileManager.default.temporaryDirectory.appending(path: "cadtools-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = try ExportPath.resolve("sub/a.stl", in: folder, format: .stl, overwrite: false)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "sub"), withDestinationURL: outside)

        #expect(await Self.failure(of: destination) != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    private static func failure(of destination: ExportDestination) async -> ExportError? {
        do {
            try await destination.write { (url) throws(ExportError) in try writeOurs(to: url) }
            return nil
        } catch {
            return error
        }
    }

    private static func writeOurs(to url: URL) throws(ExportError) {
        do { try Data("ours".utf8).write(to: url) } catch { throw ExportError("\(error)") }
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
