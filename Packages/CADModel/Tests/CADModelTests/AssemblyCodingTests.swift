@testable import CADModel
import Foundation
import Testing

@Suite("Assembly coding")
struct AssemblyCodingTests {
    private let plate = Part(name: "Plate")
    private let spacer = Part(name: "Spacer")

    @Test("An assembly with placed instances round-trips through JSON")
    func roundTrip() throws {
        let document = CADDocument(
            parameters: [Parameter(name: "gap", expression: 5)],
            parts: [plate, spacer],
            assembly: Assembly(instances: [
                Instance(name: "Base", part: plate.id, grounded: true),
                Instance(
                    name: "Middle", part: spacer.id, body: "Body1",
                    placement: Placement(translation: Vector3(20, 10, "gap"))
                ),
                Instance(
                    name: "Lid", part: plate.id,
                    placement: Placement(
                        translation: Vector3(0, 0, 15), rotationAxis: Vector3(0, 0, 1), rotationDegrees: 90
                    )
                ),
            ])
        )
        let data = try document.jsonData()
        let text = String(decoding: data, as: UTF8.self)

        #expect(try CADDocument(json: data) == document)
        #expect(text.contains("\"grounded\" : true"))
        #expect(text.contains("\"part\" : \"\(plate.id.uuidString)\""))
    }

    @Test("An instance needs only a name and a part")
    func defaults() throws {
        let json = """
            {"format": 1, "units": "mm", "parts": [{"id": "\(plate.id.uuidString)", "name": "Plate"}],
             "assembly": {"instances": [{"name": "A", "part": "\(plate.id.uuidString)"}]}}
            """
        let document = try CADDocument(json: Data(json.utf8))
        let instance = try #require(document.instances.first)

        #expect(instance.name == "A")
        #expect(instance.part == plate.id)
        #expect(instance.body == nil)
        #expect(instance.placement == .identity)
        #expect(instance.grounded == false)
        #expect(document.instance(named: "A") == instance)
        #expect(document.part(id: plate.id)?.name == "Plate")
    }

    @Test("Documents from earlier layers load: no assembly, or an empty one")
    func earlierDocumentsLoad() throws {
        let none = try CADDocument(json: Data(#"{"format": 1, "units": "mm", "parts": []}"#.utf8))
        let empty = try CADDocument(json: Data(#"{"format": 1, "units": "mm", "parts": [], "assembly": {}}"#.utf8))

        #expect(none.assembly == nil)
        #expect(none.instances.isEmpty)
        #expect(empty.assembly == Assembly())
    }

    @Test("An instance may not share an id with a part")
    func duplicateInstanceID() throws {
        let document = CADDocument(
            parts: [plate], assembly: Assembly(instances: [Instance(id: plate.id, name: "A", part: plate.id)])
        )
        let data = try document.jsonData()

        #expect(throws: DocumentError.duplicateID(plate.id)) { try CADDocument(json: data) }
    }
}
