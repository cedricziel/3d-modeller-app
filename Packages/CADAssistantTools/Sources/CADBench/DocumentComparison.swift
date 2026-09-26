import CADModel

enum DocumentComparison {
    private struct Canonical: Equatable {
        let name: String
        let suppressed: Bool
        let kind: FeatureKind
    }

    static func differences(
        from seed: CADDocument, to document: CADDocument, features exemptFeatures: Set<String>,
        parameters exemptParameters: Set<String>, instances exemptInstances: Set<String> = [], allowNewFeatures: Bool
    ) -> [String] {
        var differences: [String] = []
        let current = Dictionary(
            document.parameters.map { ($0.name, $0.expression) }, uniquingKeysWith: { first, _ in first })
        for parameter in seed.parameters where !exemptParameters.contains(parameter.name) {
            guard let expression = current[parameter.name] else {
                differences.append("parameter \(parameter.name) was removed")
                continue
            }
            if expression != parameter.expression {
                differences.append("parameter \(parameter.name) changed from \(parameter.expression) to \(expression)")
            }
        }
        for part in seed.parts {
            guard let edited = document.parts.first(where: { $0.name == part.name }) else {
                differences.append("part \(part.name) was removed")
                continue
            }
            let seedNames = Set(part.features.map(\.name))
            let before = canonical(part).filter { !exemptFeatures.contains($0.name) }
            let after = canonical(edited).filter {
                !exemptFeatures.contains($0.name) && (seedNames.contains($0.name) || !allowNewFeatures)
            }
            let afterByName = Dictionary(after.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            let beforeNames = Set(before.map(\.name))
            var changed = false
            for feature in before {
                guard let match = afterByName[feature.name] else {
                    differences.append("feature \(feature.name) was removed")
                    changed = true
                    continue
                }
                if match != feature {
                    differences.append("feature \(feature.name) changed")
                    changed = true
                }
            }
            for feature in after where !beforeNames.contains(feature.name) {
                differences.append("feature \(feature.name) was added")
                changed = true
            }
            if !changed, before.map(\.name) != after.map(\.name) {
                differences.append("features of part \(part.name) were reordered")
            }
        }
        let seedParts = Set(seed.parts.map(\.name))
        for part in document.parts where !seedParts.contains(part.name) {
            differences.append("part \(part.name) was added")
        }
        return differences + instanceDifferences(from: seed, to: document, exempt: exemptInstances)
    }

    private struct PlacedInstance: Equatable {
        let part: String?
        let body: String?
        let placement: Placement
        let grounded: Bool

        init(_ instance: Instance, in document: CADDocument) {
            part = document.part(id: instance.part)?.name
            body = instance.body
            placement = instance.placement
            grounded = instance.grounded
        }
    }

    /// Instances by name, with the part they place by name, so re-created parts with new ids compare equal.
    private static func instanceDifferences(from seed: CADDocument, to document: CADDocument, exempt: Set<String>)
        -> [String]
    {
        var differences: [String] = []
        let current = Dictionary(
            document.instances.map { ($0.name, PlacedInstance($0, in: document)) },
            uniquingKeysWith: { first, _ in first })
        for instance in seed.instances where !exempt.contains(instance.name) {
            guard let edited = current[instance.name] else {
                differences.append("instance \(instance.name) was removed")
                continue
            }
            if edited != PlacedInstance(instance, in: seed) { differences.append("instance \(instance.name) changed") }
        }
        let seedNames = Set(seed.instances.map(\.name))
        for instance in document.instances where !seedNames.contains(instance.name) && !exempt.contains(instance.name) {
            differences.append("instance \(instance.name) was added")
        }
        return differences
    }

    /// Features with each body reference replaced by the name of the feature that creates the body, so that
    /// renumbering caused by an inserted body does not look like an edit.
    private static func canonical(_ part: Part) -> [Canonical] {
        let names = Dictionary(part.features.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let creators = part.createdBodies().compactMapValues { names[$0] }
        return part.features.map { feature in
            var kind = feature.kind
            kind.renameBodyReferences { body in creators[body].map { "@\($0)" } ?? body }
            return Canonical(name: feature.name, suppressed: feature.suppressed, kind: kind)
        }
    }
}
