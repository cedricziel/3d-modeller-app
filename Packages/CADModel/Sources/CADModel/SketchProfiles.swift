import Foundation
import simd

/// A curve of a loop, oriented along the loop.
public enum SketchCurveGeometry: Sendable, Hashable {
    case line(SIMD2<Double>, SIMD2<Double>)
    /// Runs from `start` through `mid` to `end`.
    case arc(center: SIMD2<Double>, radius: Double, start: SIMD2<Double>, mid: SIMD2<Double>, end: SIMD2<Double>)
    case circle(center: SIMD2<Double>, radius: Double)

    public var start: SIMD2<Double> {
        switch self {
        case let .line(start, _), let .arc(_, _, start, _, _): start
        case let .circle(center, radius): center + SIMD2(radius, 0)
        }
    }

    public var end: SIMD2<Double> {
        switch self {
        case let .line(_, end), let .arc(_, _, _, _, end): end
        case .circle: start
        }
    }

    /// Points along the curve from its start, excluding its end, every 5° or finer on arcs and circles.
    var samples: [SIMD2<Double>] {
        switch self {
        case let .line(start, _):
            return [start]
        case let .circle(center, radius):
            return (0..<72).map { center + radius * SIMD2(cos(Double($0) * .pi / 36), sin(Double($0) * .pi / 36)) }
        case let .arc(center, radius, start, mid, end):
            let (from, sweep) = Self.sweep(center: center, start: start, mid: mid, end: end)
            let count = max(2, Int((abs(sweep) / (.pi / 36)).rounded(.up)))
            return (0..<count).map { index in
                let angle = from + sweep * Double(index) / Double(count)
                return center + radius * SIMD2(cos(angle), sin(angle))
            }
        }
    }

    /// The start angle and the signed sweep (positive counter-clockwise) of an arc through `mid`.
    static func sweep(center: SIMD2<Double>, start: SIMD2<Double>, mid: SIMD2<Double>, end: SIMD2<Double>)
        -> (from: Double, sweep: Double)
    {
        func angle(_ p: SIMD2<Double>) -> Double {
            atan2(p.y - center.y, p.x - center.x)
        }
        func span(_ a: Double, _ b: Double) -> Double {
            let d = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
            return d < 0 ? d + 2 * .pi : d
        }
        let (s, m, e) = (angle(start), angle(mid), angle(end))
        return span(s, m) <= span(s, e) ? (s, span(s, e)) : (s, -span(e, s))
    }
}

public struct SketchCurve: Sendable, Hashable {
    /// The name of the sketch entity the curve is.
    public var entity: String
    public var geometry: SketchCurveGeometry

    public init(entity: String, geometry: SketchCurveGeometry) {
        self.entity = entity
        self.geometry = geometry
    }
}

public struct SketchLoop: Sendable, Equatable {
    public var curves: [SketchCurve]
    /// How many other loops enclose this one.
    public var depth: Int
    public var area: Double
    /// The index of the smallest loop enclosing this one.
    var parent: Int?
}

public struct SketchRegion: Sendable, Equatable {
    public var outer: [SketchCurve]
    public var holes: [[SketchCurve]]

    public init(outer: [SketchCurve], holes: [[SketchCurve]]) {
        self.outer = outer
        self.holes = holes
    }
}

/// The closed loops of a sketch's solid (non-construction) lines, arcs and circles, and where they do not close.
public struct SketchProfiles: Sendable, Equatable {
    static let tolerance = 1e-4

    public var loops: [SketchLoop] = []
    /// Free curve ends, such as `line3.end (12, 5)`.
    public var openEnds: [String] = []
    /// Points where three or more curve ends meet, such as `(10, 0): line1.end, line2.start, line5.start`.
    public var branchPoints: [String] = []
    private var entityNames: Set<String> = []

    public init(_ entities: [SketchEntity]) {
        entityNames = Set(entities.map(\.name))
        var graph = Graph()
        for entity in entities where !entity.construction {
            switch entity.geometry {
            case .point:
                continue
            case let .circle(center, radius):
                loops.append(
                    SketchLoop(
                        curves: [
                            SketchCurve(entity: entity.name, geometry: .circle(center: center.simd, radius: radius))
                        ],
                        depth: 0, area: 0
                    )
                )
            case let .line(start, end):
                graph.add(entity.name, .line(start.simd, end.simd))
            case let .arc(center, radius, startAngle, endAngle):
                let (from, to) = (startAngle * .pi / 180, Self.counterClockwiseEnd(startAngle, endAngle) * .pi / 180)
                func point(_ angle: Double) -> SIMD2<Double> {
                    center.simd + radius * SIMD2(cos(angle), sin(angle))
                }
                graph.add(
                    entity.name,
                    .arc(
                        center: center.simd, radius: radius, start: point(from), mid: point((from + to) / 2),
                        end: point(to)
                    )
                )
            }
        }
        openEnds = graph.openEnds
        branchPoints = graph.branchPoints
        loops += graph.loops().map { SketchLoop(curves: $0, depth: 0, area: 0) }
        nest()
    }

    static func counterClockwiseEnd(_ start: Double, _ end: Double) -> Double {
        var end = end
        while end <= start {
            end += 360
        }
        while end - start > 360 {
            end -= 360
        }
        return end
    }

    private mutating func nest() {
        let polygons = loops.map { $0.curves.flatMap(\.geometry.samples) }
        for index in loops.indices {
            loops[index].area = abs(Self.signedArea(polygons[index]))
        }
        for index in loops.indices {
            let probe = loops[index].curves[0].geometry.samples[0]
            let enclosing = loops.indices.filter { other in
                other != index && loops[other].area > loops[index].area
                    && Self.contains(polygons[other], probe)
            }
            loops[index].depth = enclosing.count
            loops[index].parent = enclosing.min { loops[$0].area < loops[$1].area }
        }
    }

    /// The regions to sweep: every loop at an even depth when `selection` is empty, else the loops holding the
    /// named entities; each with the loops directly inside it as holes.
    public func regions(selecting selection: [String]) throws(FeatureError) -> [SketchRegion] {
        guard branchPoints.isEmpty else {
            throw .sketch(
                "the profile is ambiguous where three or more curves meet: \(branchPoints.joined(separator: "; "))"
            )
        }
        var outers: [Int] = []
        if selection.isEmpty {
            outers = loops.indices.filter { loops[$0].depth % 2 == 0 }
            guard !outers.isEmpty else {
                let ends = openEnds.isEmpty ? "" : "; open ends: \(openEnds.joined(separator: ", "))"
                throw .sketch("the sketch has no closed profile\(ends)")
            }
        } else {
            for name in selection {
                guard let index = loops.firstIndex(where: { $0.curves.contains { $0.entity == name } }) else {
                    guard entityNames.contains(name) else { throw .sketch("no entity named '\(name)' in the sketch") }
                    throw .sketch("\(name) is not part of a closed loop")
                }
                if !outers.contains(index) {
                    outers.append(index)
                }
            }
        }
        return outers.map { outer in
            SketchRegion(
                outer: loops[outer].curves,
                holes: loops.indices.filter { loops[$0].parent == outer }.map { loops[$0].curves }
            )
        }
    }

    static func signedArea(_ polygon: [SIMD2<Double>]) -> Double {
        zip(polygon, polygon.dropFirst() + polygon.prefix(1)).reduce(0) { $0 + ($1.0.x * $1.1.y - $1.1.x * $1.0.y) }
            / 2
    }

    static func contains(_ polygon: [SIMD2<Double>], _ point: SIMD2<Double>) -> Bool {
        var inside = false
        for (a, b) in zip(polygon, polygon.dropFirst() + polygon.prefix(1))
        where (a.y > point.y) != (b.y > point.y) {
            let x = a.x + (point.y - a.y) / (b.y - a.y) * (b.x - a.x)
            if point.x < x {
                inside.toggle()
            }
        }
        return inside
    }
}

/// Curve ends merged into nodes, for walking loops.
private struct Graph {
    struct End {
        let curve: Int
        let isStart: Bool
    }

    var curves: [SketchCurve] = []
    var nodes: [SIMD2<Double>] = []
    var ends: [[End]] = []
    /// The start and end node of each curve.
    var curveNodes: [(start: Int, end: Int)] = []

    mutating func add(_ name: String, _ geometry: SketchCurveGeometry) {
        let index = curves.count
        curves.append(SketchCurve(entity: name, geometry: geometry))
        let start = node(at: geometry.start)
        ends[start].append(End(curve: index, isStart: true))
        let end = node(at: geometry.end)
        ends[end].append(End(curve: index, isStart: false))
        curveNodes.append((start, end))
    }

    private mutating func node(at point: SIMD2<Double>) -> Int {
        if let index = nodes.firstIndex(where: { simd_distance($0, point) <= SketchProfiles.tolerance }) {
            return index
        }
        nodes.append(point)
        ends.append([])
        return nodes.count - 1
    }

    private func label(_ end: End) -> String {
        "\(curves[end.curve].entity).\(end.isStart ? "start" : "end")"
    }

    var openEnds: [String] {
        nodes.indices.filter { ends[$0].count == 1 }
            .sorted { a, b in
                let (x, y) = (ends[a][0], ends[b][0])
                return (x.curve, x.isStart ? 0 : 1) < (y.curve, y.isStart ? 0 : 1)
            }
            .map { "\(label(ends[$0][0])) \(Self.format(nodes[$0]))" }
    }

    var branchPoints: [String] {
        nodes.indices.filter { ends[$0].count > 2 }.map { node in
            "\(Self.format(nodes[node])): \(ends[node].map(label).sorted().joined(separator: ", "))"
        }
    }

    /// Every closed chain whose nodes all join exactly two curve ends, with curves oriented along the chain and
    /// their ends snapped to the shared nodes.
    func loops() -> [[SketchCurve]] {
        var used = Set<Int>()
        var loops: [[SketchCurve]] = []
        for first in curves.indices where !used.contains(first) {
            var chain: [SketchCurve] = []
            var closed = false
            var curve = first
            var from = curveNodes[first].start
            var visited = Set<Int>()
            while ends[from].count == 2, visited.insert(curve).inserted {
                let forward = curveNodes[curve].start == from
                let to = forward ? curveNodes[curve].end : curveNodes[curve].start
                chain.append(oriented(curve, from: nodes[from], to: nodes[to]))
                guard ends[to].count == 2 else { break }
                if to == curveNodes[first].start {
                    closed = true
                    break
                }
                guard let next = ends[to].first(where: { $0.curve != curve })?.curve else { break }
                curve = next
                from = to
            }
            used.formUnion(visited)
            if closed {
                loops.append(chain)
            }
        }
        return loops
    }

    private func oriented(_ index: Int, from: SIMD2<Double>, to: SIMD2<Double>) -> SketchCurve {
        let curve = curves[index]
        let geometry: SketchCurveGeometry =
            switch curve.geometry {
            case .line: .line(from, to)
            case let .arc(center, radius, _, mid, _):
                .arc(center: center, radius: radius, start: from, mid: mid, end: to)
            case .circle: curve.geometry
            }
        return SketchCurve(entity: curve.entity, geometry: geometry)
    }

    static func format(_ point: SIMD2<Double>) -> String {
        "(\(Scalar.format((point.x * 1e6).rounded() / 1e6)), \(Scalar.format((point.y * 1e6).rounded() / 1e6)))"
    }
}
