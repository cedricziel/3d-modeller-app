import Foundation
import Testing
@testable import CADModel

@Suite("Document coding")
struct DocumentCodingTests {
    static let handWritten = """
        {
          "format": 1,
          "units": "mm",
          "parameters": [
            { "name": "width", "expression": 60 },
            { "name": "hole_r", "expression": "width / 12" }
          ],
          "parts": [
            {
              "name": "Plate",
              "features": [
                { "name": "Base", "kind": { "type": "box", "width": "width", "depth": 40, "height": 10 } },
                { "name": "Hole", "kind": {
                    "type": "cylinder", "radius": "hole_r", "height": 10,
                    "placement": { "translation": { "x": 30, "y": 20 } },
                    "operation": { "mode": "cut", "body": "Body1" } } },
                { "name": "Pin", "suppressed": true, "kind": {
                    "type": "cone", "bottomRadius": 2, "topRadius": 1, "height": 5,
                    "placement": { "rotationAxis": { "x": 1 }, "rotationDegrees": 90 } } },
                { "name": "Ring", "kind": { "type": "torus", "majorRadius": 8, "minorRadius": 2 } },
                { "name": "Ball", "kind": { "type": "sphere", "radius": 3 } },
                { "name": "Merge", "kind": { "type": "boolean", "operation": "union", "target": "Body2", "tools": ["Body3"] } },
                { "name": "Lift", "kind": { "type": "transform", "body": "Body2",
                    "placement": { "translation": { "z": "width" } } } }
              ]
            }
          ]
        }
        """

    @Test("A hand-written file decodes with defaults filled in")
    func decodesHandWritten() throws {
        let document = try CADDocument(json: Data(Self.handWritten.utf8))
        #expect(
            document.parameters == [
                Parameter(name: "width", expression: 60), Parameter(name: "hole_r", expression: "width / 12"),
            ])
        #expect(document.assembly == nil)
        let features = try #require(document.parts.first).features
        #expect(features.map(\.name) == ["Base", "Hole", "Pin", "Ring", "Ball", "Merge", "Lift"])
        #expect(features[0].kind == .primitive(PrimitiveFeature(.box(width: "width", depth: 40, height: 10))))
        #expect(features[0].suppressed == false)
        #expect(
            features[1].kind
                == .primitive(
                    PrimitiveFeature(
                        .cylinder(radius: "hole_r", height: 10),
                        placement: Placement(translation: Vector3(30, 20, 0)),
                        operation: .cut("Body1"))))
        #expect(features[2].suppressed)
        #expect(
            features[2].kind
                == .primitive(
                    PrimitiveFeature(
                        .cone(bottomRadius: 2, topRadius: 1, height: 5),
                        placement: Placement(rotationAxis: Vector3(1, 0, 0), rotationDegrees: 90))))
        #expect(features[5].kind == .boolean(BooleanFeature(operation: .union, target: "Body2", tools: ["Body3"])))
        #expect(
            features[6].kind
                == .transform(
                    TransformFeature(
                        body: "Body2", placement: Placement(translation: Vector3(0, 0, "width")))))
    }

    @Test("Encoding is pretty, key-sorted, reserves the assembly key and round-trips")
    func roundTrip() throws {
        let document = try CADDocument(json: Data(Self.handWritten.utf8))
        let data = try document.jsonData()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\n  \"assembly\" : null,\n  \"format\" : 1,"))
        #expect(text.contains("\"expression\" : \"width / 12\""))
        #expect(try CADDocument(json: data) == document)
        #expect(try document.jsonData() == data)
    }

    @Test("A new document has one empty part")
    func newDocument() throws {
        let document = CADDocument()
        #expect(document.parts.count == 1)
        #expect(document.parts[0].name == "Part1")
        #expect(document.parts[0].features.isEmpty)
        #expect(try CADDocument(json: document.jsonData()) == document)
    }

    @Test("Other formats and units are refused")
    func refusesForeignFiles() {
        #expect(throws: DocumentError.unsupportedFormat(2)) {
            try CADDocument(json: Data(#"{"format": 2, "units": "mm", "parameters": [], "parts": []}"#.utf8))
        }
        #expect(throws: DocumentError.unsupportedUnits("in")) {
            try CADDocument(json: Data(#"{"format": 1, "units": "in", "parameters": [], "parts": []}"#.utf8))
        }
    }

    @Test(
        "Malformed features are decoding errors",
        arguments: [
            #"{"type": "fillet", "radius": 1}"#,
            #"{"type": "box", "width": 1, "depth": 1}"#,
            #"{"type": "box", "width": 1, "depth": 1, "height": 1, "operation": "cut"}"#,
            #"{"type": "box", "width": 1, "depth": 1, "height": 1, "operation": {"mode": "cut"}}"#,
            #"{"type": "boolean", "operation": "xor", "target": "Body1", "tools": []}"#,
            #"{"type": "sphere", "radius": true}"#,
        ])
    func malformedFeatures(kind: String) {
        let json =
            #"{"format": 1, "units": "mm", "parts": [{"name": "P", "features": [{"name": "F", "kind": \#(kind)}]}]}"#
        #expect(throws: DecodingError.self) { try CADDocument(json: Data(json.utf8)) }
    }

    @Test(
        "Every solid operation round-trips",
        arguments: [
            SolidOperation.newBody, .join("Body1"), .cut("Body2"), .intersect("Body3"),
        ])
    func operations(operation: SolidOperation) throws {
        let data = try JSONEncoder().encode(operation)
        #expect(try JSONDecoder().decode(SolidOperation.self, from: data) == operation)
    }

    @Test("Two features or parts sharing an id are refused")
    func duplicateIDs() throws {
        let id = "8E1C6B55-0000-4000-8000-000000000001"
        let uuid = try #require(UUID(uuidString: id))
        let features = """
            {"format": 1, "units": "mm", "parts": [{"name": "P", "features": [
              {"id": "\(id)", "name": "A", "kind": {"type": "sphere", "radius": 1}},
              {"id": "\(id)", "name": "B", "kind": {"type": "sphere", "radius": 2}}]}]}
            """
        #expect(throws: DocumentError.duplicateID(uuid)) { try CADDocument(json: Data(features.utf8)) }
        let parts = """
            {"format": 1, "units": "mm", "parts": [{"id": "\(id)", "name": "P"}, {"id": "\(id)", "name": "Q"}]}
            """
        #expect(throws: DocumentError.duplicateID(uuid)) { try CADDocument(json: Data(parts.utf8)) }
    }
}
