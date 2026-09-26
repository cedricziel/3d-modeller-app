@testable import CADModel
import Foundation
import Testing

@Suite("Joint coding")
struct JointCodingTests {
    private let box = Part(name: "Box")
    private let lid = Part(name: "Lid")

    private func document(joints: [Joint]) -> (CADDocument, Instance, Instance) {
        let base = Instance(name: "Base", part: box.id, grounded: true)
        let top = Instance(name: "Top", part: lid.id)
        let document = CADDocument(
            parameters: [Parameter(name: "gap", expression: 2)], parts: [box, lid],
            assembly: Assembly(instances: [base, top], joints: joints))
        return (document, base, top)
    }

    @Test("A joint with an edge, an offset, limits and flip round-trips through JSON")
    func roundTrip() throws {
        let (plain, base, top) = document(joints: [])
        var document = plain
        document.assembly?.joints = [
            Joint(
                name: "Hinge", kind: .revolute,
                a: JointFrameRef(
                    instance: base.id, face: .name("Box1.top"), edge: .name("edge(Box1.top, Box1.front)"),
                    offset: JointOffset(z: "gap", angle: 90)),
                b: JointFrameRef(instance: top.id, body: "Body1", face: .filter("faces normal -Z")),
                flip: true, limits: JointLimits(min: 0, max: "gap * 10"))
        ]
        let data = try document.jsonData()
        #expect(try CADDocument(json: data) == document)
        #expect(String(decoding: data, as: UTF8.self).contains("\"kind\" : \"revolute\""))
    }

    @Test("Documents saved before joints existed load with none")
    func earlierDocumentsLoad() throws {
        let json = """
            {"format": 1, "units": "mm", "parts": [{"id": "\(box.id.uuidString)", "name": "Box"}],
             "assembly": {"instances": [{"name": "A", "part": "\(box.id.uuidString)"}]}}
            """
        let document = try CADDocument(json: Data(json.utf8))
        #expect(document.assembly?.joints == [])
        #expect(document.joints.isEmpty)
    }

    @Test("A joint needs only a name, a kind and two faces")
    func defaults() throws {
        let instance = UUID()
        let json = """
            {"name": "Mate", "kind": "fixed", "a": {"instance": "\(instance.uuidString)", "face": {"name": "Box1.top"}},
             "b": {"instance": "\(instance.uuidString)", "face": {"name": "Lid1.bottom"}}}
            """
        let joint = try JSONDecoder().decode(Joint.self, from: Data(json.utf8))
        #expect(joint.flip == false)
        #expect(joint.limits == nil)
        #expect(joint.a.edge == nil)
        #expect(joint.a.offset == nil)
        #expect(joint.b.face == .name("Lid1.bottom"))
    }

    @Test("An unknown joint kind is refused")
    func unknownKind() {
        let json = """
            {"name": "Mate", "kind": "weld", "a": {"instance": "\(UUID().uuidString)", "face": {"name": "A.top"}},
             "b": {"instance": "\(UUID().uuidString)", "face": {"name": "B.top"}}}
            """
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Joint.self, from: Data(json.utf8)) }
    }

    @Test("A joint sharing an instance's id is refused")
    func duplicateJointID() throws {
        let (plain, base, top) = document(joints: [])
        var document = plain
        document.assembly?.joints = [
            Joint(
                id: base.id, name: "Mate", kind: .fixed, a: JointFrameRef(instance: base.id, face: .name("Box1.top")),
                b: JointFrameRef(instance: top.id, face: .name("Lid1.bottom")))
        ]
        let data = try document.jsonData()
        #expect(throws: DocumentError.duplicateID(base.id)) { try CADDocument(json: data) }
    }
}
