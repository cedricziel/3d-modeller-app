import Foundation

/// A part's bodies at the part's own coordinates, written once however often it is placed.
public struct ExportProduct<Body: Sendable>: Sendable {
    public var name: String
    public var bodies: [(name: String, body: Body)]
    public var color: SIMD3<Double>

    public init(name: String, bodies: [(name: String, body: Body)], color: SIMD3<Double>) {
        self.name = name
        self.bodies = bodies
        self.color = color
    }
}

/// A product placed where the assembly puts an instance.
public struct ExportOccurrence: Sendable, Equatable {
    public var name: String
    public var product: Int
    public var transform: RigidTransform

    public init(name: String, product: Int, transform: RigidTransform) {
        self.name = name
        self.product = product
        self.transform = transform
    }
}

public struct ExportScene<Body: Sendable>: Sendable {
    /// The name of the root assembly, when there are occurrences.
    public var name: String
    public var products: [ExportProduct<Body>]
    /// Without occurrences, each product stands on its own at its coordinates.
    public var occurrences: [ExportOccurrence]
    /// What was left out, and why.
    public var skipped: [String]

    public init(
        name: String, products: [ExportProduct<Body>], occurrences: [ExportOccurrence], skipped: [String] = []
    ) {
        self.name = name
        self.products = products
        self.occurrences = occurrences
        self.skipped = skipped
    }

    public func map<Other: Sendable>(_ transform: (Body) throws(ExportError) -> Other) throws(ExportError)
        -> ExportScene<Other>
    {
        var products: [ExportProduct<Other>] = []
        for product in self.products {
            var bodies: [(name: String, body: Other)] = []
            for (name, body) in product.bodies {
                bodies.append((name, try transform(body)))
            }
            products.append(ExportProduct(name: product.name, bodies: bodies, color: product.color))
        }
        return ExportScene<Other>(name: name, products: products, occurrences: occurrences, skipped: skipped)
    }

    /// Each body where it ends up: once per occurrence, or where the product has it when there are none.
    public var placedBodies: [(body: Body, transform: RigidTransform)] {
        guard !occurrences.isEmpty else {
            return products.flatMap { $0.bodies.map { ($0.body, RigidTransform.identity) } }
        }
        return occurrences.flatMap { occurrence in
            products[occurrence.product].bodies.map { ($0.body, occurrence.transform) }
        }
    }
}

public enum ExportPlan {
    /// The products and occurrences `target` exports from `result`; `built` holds the bodies the kernel has.
    public static func scene(_ target: ExportTarget, in result: RebuildResult, built: Set<BodyKey>)
        throws(ExportError) -> ExportScene<BodyKey>
    {
        var planner = Planner(result: result, built: built)
        switch target {
        case .document:
            if let instances = result.assembly?.instances, !instances.isEmpty {
                instances.forEach { planner.place($0) }
            } else {
                result.parts.forEach { planner.addPart($0) }
            }
        case .part(let id):
            planner.addPart(try part(id, in: result))
        case .body(let id, let name):
            let part = try part(id, in: result)
            guard part.bodies.contains(where: { $0.name == name }) else {
                let names = part.bodies.map(\.name).joined(separator: ", ")
                throw ExportError("\(part.name) has no body named \(name); bodies: \(names.isEmpty ? "none" : names)")
            }
            planner.addProduct(
                name: part.bodies.count > 1 ? "\(part.name)/\(name)" : part.name, part: part, bodies: [name])
        case .instance(let id):
            guard let instance = result.assembly?.instance(id: id) else {
                let names = (result.assembly?.instances ?? []).map(\.name).joined(separator: ", ")
                throw ExportError("No instance with id \(id); instances: \(names.isEmpty ? "none" : names)")
            }
            planner.place(instance)
        }
        guard !planner.products.isEmpty else {
            let reasons = planner.skipped.isEmpty ? "the model has no bodies" : planner.skipped.joined(separator: "; ")
            throw ExportError("Nothing to export: \(reasons)")
        }
        let name = target == .document && !planner.occurrences.isEmpty ? "Assembly" : planner.products[0].name
        var seen: Set<String> = []
        return ExportScene(
            name: name, products: planner.products, occurrences: planner.occurrences,
            skipped: planner.skipped.filter { seen.insert($0).inserted })
    }

    private static func part(_ id: UUID, in result: RebuildResult) throws(ExportError) -> PartResult {
        guard let part = result.parts.first(where: { $0.id == id }) else {
            let names = result.parts.map(\.name).joined(separator: ", ")
            throw ExportError("No part with id \(id); parts: \(names.isEmpty ? "none" : names)")
        }
        return part
    }
}

private struct Planner {
    let result: RebuildResult
    let built: Set<BodyKey>
    var products: [ExportProduct<BodyKey>] = []
    var occurrences: [ExportOccurrence] = []
    var skipped: [String] = []
    private var productIndex: [String: Int] = [:]

    init(result: RebuildResult, built: Set<BodyKey>) {
        self.result = result
        self.built = built
    }

    mutating func addPart(_ part: PartResult) {
        addProduct(name: part.name, part: part, bodies: part.bodies.map(\.name))
    }

    /// The product's index, or nil when none of its bodies was built.
    @discardableResult
    mutating func addProduct(name: String, part: PartResult, bodies: [String]) -> Int? {
        if let index = productIndex[name] { return index }
        var keys: [(name: String, body: BodyKey)] = []
        for body in bodies {
            let key = BodyKey(part: part.id, body: body)
            if built.contains(key) {
                keys.append((body, key))
            } else {
                skipped.append("\(part.name)/\(body) (not built)")
            }
        }
        guard !keys.isEmpty else {
            if bodies.isEmpty { skipped.append("\(name) (no bodies)") }
            return nil
        }
        products.append(ExportProduct(name: name, bodies: keys, color: ExportPalette.color(products.count)))
        productIndex[name] = products.count - 1
        return products.count - 1
    }

    mutating func place(_ instance: InstanceResult) {
        guard case .ok = instance.status, let transform = instance.transform else {
            skipped.append("\(instance.name) (\(instance.status))")
            return
        }
        guard let part = result.parts.first(where: { $0.id == instance.part }) else {
            skipped.append("\(instance.name) (its part is missing)")
            return
        }
        let bodies = instance.bodies.map(\.name)
        let whole = bodies == part.bodies.map(\.name)
        let name = whole || part.bodies.count == 1 ? part.name : "\(part.name)/\(bodies.joined(separator: "+"))"
        guard let product = addProduct(name: name, part: part, bodies: bodies) else {
            skipped.append("\(instance.name) (no bodies)")
            return
        }
        occurrences.append(ExportOccurrence(name: instance.name, product: product, transform: transform))
    }
}
