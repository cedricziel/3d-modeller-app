import CADModel
import Foundation

extension CADSession {
    /// Deletes a feature the way `delete_feature` does, repairing body references or refusing when another feature
    /// uses its body. Returns nil when the feature was deleted, otherwise why not.
    public func deleteFeature(id: UUID) async -> String? {
        let result = await write { (document) throws(ToolError) in
            for part in document.parts.indices {
                if let index = document.parts[part].features.firstIndex(where: { $0.id == id }) {
                    let feature = document.parts[part].features.remove(at: index)
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
