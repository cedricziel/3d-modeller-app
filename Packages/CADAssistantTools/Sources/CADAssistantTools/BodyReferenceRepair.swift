import CADModel
import Foundation

/// Bodies are named by the order of the features that create them, so adding, deleting or changing a creating
/// feature renames every later body. This keeps each reference pointing at the same creating feature, and refuses
/// the edit when a referenced body would stop existing.
enum BodyReferenceRepair {
    static func apply(from before: CADDocument, to after: inout CADDocument) throws(ToolError) -> [String] {
        var notes: [String] = []
        var conflicts: [String] = []
        for partIndex in after.parts.indices {
            guard let old = before.parts.first(where: { $0.id == after.parts[partIndex].id }) else { continue }
            let owners = old.createdBodies()
            let newNames = Dictionary(uniqueKeysWithValues: after.parts[partIndex].createdBodies().map { ($1, $0) })
            for featureIndex in after.parts[partIndex].features.indices {
                let feature = after.parts[partIndex].features[featureIndex]
                var renamed: [String] = []
                var kind = feature.kind
                kind.renameBodyReferences { name in
                    guard let owner = owners[name] else { return name }
                    guard let newName = newNames[owner] else {
                        let creator = old.features.first { $0.id == owner }?.name ?? "?"
                        conflicts.append("\(feature.name) uses \(name), which \(creator) creates")
                        return name
                    }
                    if newName != name { renamed.append("\(newName) (was \(name))") }
                    return newName
                }
                after.parts[partIndex].features[featureIndex].kind = kind
                if !renamed.isEmpty {
                    notes.append("\(feature.name) now refers to \(renamed.joined(separator: ", "))")
                }
            }
            for index in after.instances.indices where after.instances[index].part == old.id {
                let instance = after.instances[index]
                guard let name = instance.body, let owner = owners[name] else { continue }
                guard let newName = newNames[owner] else {
                    let creator = old.features.first { $0.id == owner }?.name ?? "?"
                    conflicts.append("\(instance.name) uses \(name), which \(creator) creates")
                    continue
                }
                guard newName != name else { continue }
                after.assembly?.instances[index].body = newName
                notes.append("\(instance.name) now refers to \(newName) (was \(name))")
            }
        }
        guard conflicts.isEmpty else {
            throw ToolError(
                "Nothing changed, because bodies that other features or instances use would no longer exist: "
                    + conflicts.joined(separator: "; ")
                    + ". Change or delete those features first, or suppress the creating feature instead.")
        }
        return notes
    }
}
