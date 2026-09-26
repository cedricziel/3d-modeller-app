import CADModel
import SwiftUIAssistant

/// A placement argument whose given components replace those of an existing placement.
struct PlacementArguments {
    var translation: [String: Scalar] = [:]
    var rotationAxis: [String: Scalar] = [:]
    var rotationDegrees: Scalar?

    init(_ object: [String: JSONValue], key: String = "placement") throws(ToolError) {
        let arguments = try Arguments(object, allowed: ["translation", "rotationAxis", "rotationDegrees"])
        translation = try FeatureSpec.vector(object["translation"], "\(key).translation")
        rotationAxis = try FeatureSpec.vector(object["rotationAxis"], "\(key).rotationAxis")
        rotationDegrees = try arguments.scalar("rotationDegrees")
    }

    func applied(to placement: Placement) -> Placement {
        func merged(_ vector: Vector3, _ components: [String: Scalar]) -> Vector3 {
            Vector3(components["x"] ?? vector.x, components["y"] ?? vector.y, components["z"] ?? vector.z)
        }
        return Placement(
            translation: merged(placement.translation, translation),
            rotationAxis: merged(placement.rotationAxis, rotationAxis),
            rotationDegrees: rotationDegrees ?? placement.rotationDegrees)
    }
}
