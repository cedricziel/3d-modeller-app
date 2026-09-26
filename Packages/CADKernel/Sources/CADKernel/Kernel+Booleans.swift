import OCCTSwift

public enum BooleanOperation: String, Sendable, Hashable, Codable, CaseIterable {
    case union, subtract, intersect
}

extension Kernel {
    public static func boolean(
        _ operation: BooleanOperation, _ target: Solid, _ tool: Solid, feature: String = "Boolean"
    ) throws -> Solid {
        try OCCTSerial.withLock {
            let outcome =
                switch operation {
                case .union: target.shape.unionWithFullHistory(tool.shape)
                case .subtract: target.shape.subtractedWithFullHistory(tool.shape)
                case .intersect: target.shape.intersectionWithFullHistory(tool.shape)
                }
            guard let (result, history) = outcome, result.isValid else {
                throw KernelError.operationFailed("\(operation.rawValue) the solids")
            }
            guard result.solidCount > 0 else { throw KernelError.emptyResult }
            let names = Naming.carry(
                [.init(shape: target.shape, names: target.faceNames), .init(shape: tool.shape, names: tool.faceNames)],
                into: result, history: history, feature: feature)
            return Solid(shape: result, faceNames: names)
        }
    }

    public static func solids(of solid: Solid) -> [Solid] {
        OCCTSerial.withLock {
            solid.shape.solids.map { piece in
                Solid(
                    shape: piece,
                    faceNames: Naming.fillGaps(
                        Naming.names(of: piece, in: solid.shape, names: solid.faceNames), feature: "Solid"))
            }
        }
    }
}
