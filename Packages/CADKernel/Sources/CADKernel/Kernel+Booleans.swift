import OCCTSwift

public enum BooleanOperation: String, Sendable, Hashable, Codable, CaseIterable {
    case union, subtract, intersect
}

extension Kernel {
    public static func boolean(_ operation: BooleanOperation, _ target: Solid, _ tool: Solid) throws -> Solid {
        try OCCTSerial.withLock {
            let result: Shape? =
                switch operation {
                case .union: target.shape.union(tool.shape)
                case .subtract: target.shape.subtracting(tool.shape)
                case .intersect: target.shape.intersection(tool.shape)
                }
            guard let result, result.isValid else {
                throw KernelError.operationFailed("\(operation.rawValue) the solids")
            }
            guard result.solidCount > 0 else { throw KernelError.emptyResult }
            return Solid(shape: result)
        }
    }

    public static func solids(of solid: Solid) -> [Solid] {
        OCCTSerial.withLock { solid.shape.solids.map(Solid.init(shape:)) }
    }
}
