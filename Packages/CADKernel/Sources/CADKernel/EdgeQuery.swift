import OCCTSwift

public enum EdgeQuery: Sendable, Equatable {
    case parallel(to: SIMD3<Double>)

    func edges(of shape: Shape) -> [Edge] {
        switch self {
        case .parallel(let axis):
            shape.edges(parallelTo: axis)
        }
    }
}
