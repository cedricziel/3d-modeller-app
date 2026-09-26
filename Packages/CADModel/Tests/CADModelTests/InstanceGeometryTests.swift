@testable import CADModel
import Foundation
import simd
import Testing

@Suite("Instance geometry")
struct InstanceGeometryTests {
    private let noParameters = ParameterTable([])

    private func instance(_ features: [Feature], placement: Placement, body: String? = nil) async throws
        -> InstanceResult
    {
        let part = Part(name: "P", features: features)
        let document = CADDocument(
            parts: [part],
            assembly: Assembly(instances: [Instance(name: "Lid", part: part.id, body: body, placement: placement)])
        )
        return try #require(try await RebuildEngine(kernel: FakeKernel()).rebuild(document).assembly?.instances.first)
    }

    private func box(_ name: String, _ w: Scalar = 10, _ d: Scalar = 20, _ h: Scalar = 30) -> Feature {
        Feature(name: name, kind: .primitive(PrimitiveFeature(.box(width: w, depth: d, height: h))))
    }

    private let raised = Placement(translation: Vector3(0, 0, 20))

    private func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool {
        simd_distance(a, b) < 1e-9
    }

    @Test("A face name resolves on the instance, in assembly coordinates")
    func resolvesFace() async throws {
        let lid = try await instance([box("Box")], placement: raised)
        let element = try lid.element(.name("Box.top"), .faces, body: nil, parameters: noParameters)
        let face = try #require(lid.bodies.first?.topology?.faces[element.index])

        #expect(element == InstanceElement(body: "Body1", kind: .faces, index: 5, name: "Box.top"))
        #expect(face.centroid == SIMD3(5, 10, 50))
    }

    @Test("A planar face gives its centre, outward normal and the first global axis in its plane")
    func planarFrame() async throws {
        let lid = try await instance([box("Box")], placement: raised)
        let frame = try lid.frame(face: .name("Box.top"), edge: nil, body: nil, parameters: noParameters)

        #expect(close(frame.origin, SIMD3(5, 10, 50)))
        #expect(close(frame.zAxis, SIMD3(0, 0, 1)))
        #expect(close(frame.xAxis, SIMD3(1, 0, 0)))
        #expect(close(frame.yAxis, SIMD3(0, 1, 0)))
    }

    @Test("A straight edge moves the origin to its midpoint and turns x along it")
    func edgeFrame() async throws {
        let lid = try await instance([box("Box")], placement: raised)
        let frame = try lid.frame(
            face: .name("Box.right"), edge: .name("edge(Box.right, Box.top)"), body: nil, parameters: noParameters
        )

        #expect(close(frame.origin, SIMD3(10, 10, 50)))
        #expect(close(frame.zAxis, SIMD3(1, 0, 0)))
        #expect(close(frame.xAxis, SIMD3(0, 1, 0)))
        #expect(close(frame.yAxis, SIMD3(0, 0, 1)))
    }

    @Test("A cylinder gives its axis and a point on it; a circular edge gives its centre")
    func cylinderAndCircleFrames() throws {
        let side = FaceDescriptor(
            names: ["Pin.side"], surface: .cylinder, centroid: SIMD3(3, 0, 5), area: 1, axisOrigin: .zero,
            axis: SIMD3(0, 0, 1), radius: 3
        )
        let rim = EdgeDescriptor(
            faces: [0], curve: .circle, length: 1, start: .zero, end: .zero, midpoint: SIMD3(3, 0, 10),
            center: SIMD3(0, 0, 10), axis: SIMD3(0, 0, 1), radius: 3
        )
        let onAxis = try GeometryFrame.frame(face: side, edge: nil)
        let atRim = try GeometryFrame.frame(face: side, edge: rim)

        #expect(close(onAxis.origin, SIMD3(0, 0, 5)))
        #expect(close(onAxis.zAxis, SIMD3(0, 0, 1)))
        #expect(close(atRim.origin, SIMD3(0, 0, 10)))
    }

    @Test("A sphere has no axis to build a frame on")
    func sphereRefused() {
        let ball = FaceDescriptor(names: ["Ball.surface"], surface: .sphere, centroid: .zero, area: 1)

        #expect(throws: ReferenceError.self) { try GeometryFrame.frame(face: ball, edge: nil) }
    }

    @Test("A reference found in two bodies needs 'body'; an unknown body lists the bodies")
    func severalBodies() async throws {
        let lid = try await instance([box("Box"), box("Cap")], placement: raised)
        let upward = GeometryReference.filter("normal +Z")

        #expect(throws: ReferenceError("'normal +Z' matches faces in Body1 and Body2 of Lid; add 'body'")) {
            try lid.element(upward, .faces, body: nil, parameters: noParameters)
        }
        #expect(try lid.element(upward, .faces, body: "Body2", parameters: noParameters).name == "Cap.top")
        #expect(throws: ReferenceError("Lid has no body named Body7; bodies: Body1, Body2")) {
            try lid.element(upward, .faces, body: "Body7", parameters: noParameters)
        }
    }

    @Test("An instance that did not build has no geometry")
    func failedInstance() async throws {
        let lid = try await instance([box("Box")], placement: raised, body: "Body4")

        #expect(throws: ReferenceError("Lid did not build: part P has no body named Body4; bodies: Body1")) {
            try lid.element(.name("Box.top"), .faces, body: nil, parameters: noParameters)
        }
    }
}
