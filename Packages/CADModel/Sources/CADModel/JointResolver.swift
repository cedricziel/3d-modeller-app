import Foundation
import simd

/// Turns a joint's frame references into marker frames in each instance's part coordinates.
struct JointResolver {
    struct Failure: Error {
        let reason: String
    }

    let parameters: ParameterTable
    let instances: [InstanceResult]
    /// Each part's body results, by part id, in the part's own coordinates.
    let partBodies: [UUID: [BodyResult]]

    /// Half a turn about x: side b faces side a.
    static let mateTurn = RigidTransform(
        rotation: simd_double3x3(diagonal: SIMD3(1, -1, -1)), translation: .zero)

    /// The marker of one side and the instance it sits on.
    func marker(_ side: JointFrameRef, _ label: String, mate: Bool) throws(Failure) -> (InstanceResult, RigidTransform)
    {
        do throws(ReferenceError) {
            guard let instance = instances.first(where: { $0.id == side.instance }) else {
                throw ReferenceError("its instance no longer exists")
            }
            let face = try instance.element(side.face, .faces, body: side.body, parameters: parameters)
            let edge = try side.edge.map { edge throws(ReferenceError) in
                try instance.element(edge, .edges, body: face.body, parameters: parameters)
            }
            guard let topology = partBodies[instance.part]?.first(where: { $0.name == face.body })?.topology else {
                throw ReferenceError("\(instance.name)/\(face.body) has no faces")
            }
            let frame = try GeometryFrame.frame(
                face: topology.faces[face.index], edge: edge.map { topology.edges[$0.index] })
            var marker = RigidTransform(
                rotation: simd_double3x3(columns: (frame.xAxis, frame.yAxis, frame.zAxis)), translation: frame.origin)
            if let offset = side.offset { marker = marker.composed(with: try moved(by: offset)) }
            return (instance, mate ? marker.composed(with: Self.mateTurn) : marker)
        } catch {
            throw Failure(reason: "\(label): \(error.description)")
        }
    }

    private func moved(by offset: JointOffset) throws(ReferenceError) -> RigidTransform {
        var values: [Double] = []
        for (field, scalar) in offset.scalars {
            do {
                values.append(try parameters.evaluate(scalar))
            } catch {
                throw ReferenceError("offset.\(field): \(error)")
            }
        }
        let turn = simd_double3x3(simd_quatd(angle: values[3] * .pi / 180, axis: SIMD3(0, 0, 1)))
        return RigidTransform(rotation: turn, translation: SIMD3(values[0], values[1], values[2]))
    }
}
