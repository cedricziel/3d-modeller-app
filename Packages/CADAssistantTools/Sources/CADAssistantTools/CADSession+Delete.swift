import CADModel
import Foundation

extension CADSession {
    /// Deletes a feature the way `delete_feature` does, repairing body references or refusing when another feature
    /// uses its body. Returns nil when the feature was deleted, otherwise why not.
    public func deleteFeature(id: UUID) async -> String? {
        let result = await write { (document) throws(ToolError) in
            for part in document.parts.indices {
                if let index = document.parts[part].features.firstIndex(where: { $0.id == id }) {
                    let feature = try document.parts[part].removeFeature(at: index)
                    return WriteFocus(
                        actionName: "Delete \(feature.name)",
                        summary: "Deleted \(feature.name) from part \(document.parts[part].name)")
                }
            }
            throw ToolError("The feature no longer exists.")
        }
        return result.success ? nil : result.message
    }
}

extension Part {
    /// Removes the feature at `index`, refusing while an extrude or revolve uses it as its sketch.
    mutating func removeFeature(at index: Int) throws(ToolError) -> Feature {
        let name = features[index].name
        if case .sketch = features[index].kind {
            let users = features.filter { $0.kind.sketchReference == name }.map(\.name)
            guard users.isEmpty else {
                throw ToolError(
                    "Nothing changed, because \(name) is used by \(users.joined(separator: ", ")). Delete or change "
                        + "those features first, or suppress \(name) instead.")
            }
        }
        return features.remove(at: index)
    }
}
