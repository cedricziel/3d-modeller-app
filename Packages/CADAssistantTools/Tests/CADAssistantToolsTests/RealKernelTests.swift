import CADModel
import CADModelKernel
import CADModelSolvers
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("Tools on the Open CASCADE kernel")
struct RealKernelTests {
    @Test("A plate with a parametric hole has the exact volume and stays a valid closed solid")
    func plateWithHole() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "Plate")]), kernel: OCCTGeometryKernel())
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        for (name, value) in [("width", 60), ("depth", 40), ("t", 10)] as [(String, JSONValue)] {
            #expect(
                try await tools["set_parameter"]!.execute(arguments: ["name": .string(name), "expression": value])
                    .success)
        }

        _ = try await tools["add_feature"]!.execute(arguments: [
            "name": "Plate", "type": "box", "width": "width", "depth": "depth", "height": "t",
        ])
        let hole = try await tools["add_feature"]!.execute(arguments: [
            "name": "Hole", "type": "cylinder", "radius": 2.75, "height": "t",
            "placement": ["translation": ["x": "width / 2", "y": "depth / 2"]], "operation": "cut", "body": "Body1",
        ])

        #expect(hole.success)
        #expect(hole.message.contains("Hole: ok"))
        #expect(hole.message.contains("Body1 (Plate): valid closed solid, 7 faces, 15 edges, volume 23762.4"))
        #expect(hole.message.contains("bounds (0, 0, 0) to (60, 40, 10)"))
        let volume = try #require(session.result?.bodies.first?.metrics?.volume)
        #expect(abs(volume - (24000 - Double.pi * 2.75 * 2.75 * 10)) < 0.01)
    }

    @Test("A kernel failure is reported as the feature's status and the document keeps the feature")
    func kernelFailure() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "P")]), kernel: OCCTGeometryKernel())
        let add = AddFeatureTool(session: session)
        _ = try await add.execute(arguments: ["type": "box", "width": 10, "depth": 10, "height": 10])

        let result = try await add.execute(arguments: [
            "type": "box", "width": 5, "depth": 5, "height": 5, "placement": ["translation": [100, 0, 0]],
            "operation": "intersect", "body": "Body1",
        ])

        #expect(result.success)
        #expect(result.message.contains("Box2: failed:"))
        #expect(session.document.parts[0].features.count == 2)
        #expect(result.message.contains("Body1 (P): valid closed solid, 6 faces, 12 edges, volume 1000 mm³"))
    }
}

@MainActor
@Suite("Sketch tools on Open CASCADE and PlaneGCS")
struct RealSketchTests {
    @Test("A fully constrained sketch extrudes into a plate whose side faces are named after its lines")
    func sketchedPlate() async throws {
        let session = CADSession(
            document: CADDocument(parameters: Fixtures.plateParameters, parts: [Part(name: "Plate")]),
            kernel: OCCTGeometryKernel(), sketchSolver: PlaneGCSSketchSolver())
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        let sketch = try await tools["add_sketch"]!.execute(arguments: [
            "plane": "XY", "entities": SketchToolTests.rectangle,
            "constraints": [
                ["type": "coincident", "points": ["line1.end", "line2.start"]],
                ["type": "coincident", "points": ["line2.end", "line3.start"]],
                ["type": "coincident", "points": ["line3.end", "line4.start"]],
                ["type": "coincident", "points": ["line4.end", "line1.start"]],
                ["type": "horizontal", "entities": ["line1"]], ["type": "horizontal", "entities": ["line3"]],
                ["type": "vertical", "entities": ["line2"]], ["type": "vertical", "entities": ["line4"]],
                ["type": "fixed", "points": ["line1.start"], "at": [0, 0]],
                ["type": "distance", "points": ["line1.start", "line1.end"], "value": "width"],
                ["type": "distance", "points": ["line2.start", "line2.end"], "value": "depth"],
            ],
        ])
        #expect(sketch.message.contains("fully constrained; 1 region"), "\(sketch.message)")

        let extrude = try await tools["add_feature"]!.execute(arguments: [
            "type": "extrude", "sketch": "Sketch1", "distance": "t",
        ])
        #expect(extrude.message.contains("Body1 (Plate): valid closed solid, 6 faces, 12 edges, volume 24000 mm³"))
        let faces = try await tools["find_geometry"]!.execute(arguments: ["body": "Body1", "kind": "faces"])
        #expect(faces.message.contains("Extrude1.side[Sketch1.line1]  plane"))
        #expect(faces.message.contains("Extrude1.end  plane"))
    }
}

@MainActor
@Suite("Joint tools on Open CASCADE and OndselSolver")
struct RealJointTests {
    @Test("A fixed joint through the tools puts the lid flush on the box")
    func lidOnBox() async throws {
        let session = CADSession(
            document: CADDocument(parts: [Part(name: "Box"), Part(name: "Lid")]), kernel: OCCTGeometryKernel(),
            assemblySolver: OndselAssemblySolver())
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        _ = try await tools["add_feature"]!.execute(arguments: [
            "part": "Box", "name": "Shell", "type": "box", "width": 60, "depth": 40, "height": 30,
        ])
        _ = try await tools["add_feature"]!.execute(arguments: [
            "part": "Lid", "name": "Cap", "type": "box", "width": 60, "depth": 40, "height": 5,
        ])
        _ = try await tools["add_instance"]!.execute(arguments: ["part": "Box", "name": "Base", "grounded": true])
        _ = try await tools["add_instance"]!.execute(arguments: [
            "part": "Lid", "name": "Top", "placement": ["translation": [100, 0, 80]],
        ])

        let joint = try await tools["add_joint"]!.execute(arguments: [
            "kind": "fixed", "a": ["instance": "Base", "face": "Shell.top"],
            "b": ["instance": "Top", "face": "Cap.bottom"],
        ])

        #expect(joint.message.contains("Fixed1: ok"), "\(joint.message)")
        #expect(joint.message.contains("Top (Lid): ok, bounds (0, 0, 30) to (60, 40, 35)"), "\(joint.message)")
        #expect(joint.message.contains("Moved by joints: Top (100, 0, 80) → (0, 0, 30)"), "\(joint.message)")
    }

    @Test("move_joint opens a hinged lid upright, and measure sees it there")
    func moveJointOpensLid() async throws {
        let session = CADSession(
            document: CADDocument(parts: [Part(name: "Box"), Part(name: "Lid")]), kernel: OCCTGeometryKernel(),
            assemblySolver: OndselAssemblySolver())
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        _ = try await tools["add_feature"]!.execute(arguments: [
            "part": "Box", "name": "Shell", "type": "box", "width": 60, "depth": 40, "height": 30,
        ])
        _ = try await tools["add_feature"]!.execute(arguments: [
            "part": "Lid", "name": "Cap", "type": "box", "width": 60, "depth": 40, "height": 5,
        ])
        _ = try await tools["add_instance"]!.execute(arguments: ["part": "Box", "name": "Base", "grounded": true])
        _ = try await tools["add_instance"]!.execute(arguments: ["part": "Lid", "name": "Top"])
        let hinge = try await tools["add_joint"]!.execute(arguments: [
            "kind": "revolute", "name": "Hinge", "flip": true, "limits": ["min": 0, "max": 110], "value": 0,
            "a": ["instance": "Base", "face": "Shell.left", "offset": ["x": 20, "y": -15]],
            "b": ["instance": "Top", "face": "Cap.left", "offset": ["x": 20, "y": 2.5]],
        ])
        #expect(hinge.message.contains("Top (Lid): ok, bounds (0, 0, 30) to (60, 40, 35)"), "\(hinge.message)")

        let moved = try await tools["move_joint"]!.execute(arguments: ["joint": "Hinge", "value": 90])
        let measured = try await tools["measure"]!.execute(arguments: ["kind": "size", "a": ["instance": "Top"]])

        #expect(moved.message.contains("Hinge: ok, at 90° driven, limits 0°…110°, 0 dof"), "\(moved.message)")
        #expect(moved.message.contains("Top (Lid): ok, bounds (0, 40, 30) to (60, 45, 70)"), "\(moved.message)")
        #expect(measured.message.contains("(0, 40, 30)"), "\(measured.message)")
    }

    @Test("export writes a STEP assembly that reads back with every instance")
    func exportStepRoundTrip() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "Plate")]), kernel: OCCTGeometryKernel())
        let folder = FileManager.default.temporaryDirectory.appending(path: "cadtools-step-\(UUID().uuidString)")
        session.exportDirectory = folder
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        _ = try await tools["add_feature"]!.execute(arguments: [
            "name": "Base", "type": "box", "width": 60, "depth": 40, "height": 10,
        ])
        _ = try await tools["add_instance"]!.execute(arguments: ["part": "Plate", "name": "Left"])
        _ = try await tools["add_instance"]!.execute(arguments: [
            "part": "Plate", "name": "Right", "placement": ["translation": ["x": 100]],
        ])

        let exported = try await tools["export"]!.execute(arguments: ["format": "step", "path": "plates"])
        let inspection = try OCCTGeometryKernel.inspectSTEP(at: folder.appending(path: "plates.step"))
        let bounds = try #require(inspection.bounds)
        let expectedVolume = 2.0 * 60 * 40 * 10

        #expect(exported.success, "\(exported.message)")
        #expect(exported.message.contains("products Plate; occurrences Left, Right; 2 bodies."))
        #expect(inspection.solidCount == 2)
        #expect(abs(inspection.volume - expectedVolume) < 1e-3 * expectedVolume)
        #expect(abs(bounds.max.x - 160) < 1e-6)
        #expect(inspection.names.contains("Right"))
    }
}
