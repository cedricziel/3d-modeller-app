import CADModel

enum AssemblyListing {
    static func lines(_ document: CADDocument, result: RebuildResult?) -> [String] {
        guard let assembly = document.assembly else { return [] }
        guard !assembly.instances.isEmpty else { return ["assembly", "  (no instances)"] }
        return ["assembly"] + assembly.instances.map { "  " + line($0, document, result: result) }
    }

    static func line(_ instance: Instance, _ document: CADDocument, result: RebuildResult?) -> String {
        let status = result?.assembly?.instance(id: instance.id)?.status.description ?? "not built"
        return "\(instance.name)  \(summary(instance, document))  \(status)"
    }

    static func summary(_ instance: Instance, _ document: CADDocument) -> String {
        guard let part = document.part(id: instance.part) else { return "(missing part)" }
        let placed = part.name + (instance.body.map { "/\($0)" } ?? "")
        return "\(placed) \(DocumentListing.location(instance.placement))" + (instance.grounded ? ", grounded" : "")
    }
}
