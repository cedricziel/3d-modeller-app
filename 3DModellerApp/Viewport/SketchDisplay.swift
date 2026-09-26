import CADModel
import Foundation
import simd

/// Line segments that draw a solved sketch on its plane, in model millimetres.
enum SketchDisplay {
    struct Segment: Equatable {
        var start: SIMD3<Float>
        var end: SIMD3<Float>
        var construction: Bool
    }

    static let dash: Double = 2
    static let crossSize: Double = 1

    static func segments(of sketch: SketchResult) -> [Segment] {
        sketch.entities.flatMap { entity -> [Segment] in
            let pieces = polyline(entity.geometry)
            var segments: [(SIMD2<Double>, SIMD2<Double>)] = []
            for piece in pieces {
                segments += zip(piece, piece.dropFirst()).map { ($0, $1) }
            }
            if entity.construction { segments = dashed(segments) }
            return segments.map { a, b in
                Segment(
                    start: SIMD3<Float>(sketch.frame.point(a)), end: SIMD3<Float>(sketch.frame.point(b)),
                    construction: entity.construction)
            }
        }
    }

    /// Polylines through the entity: lines as they are, arcs and circles every 10° or finer, a point as a cross.
    private static func polyline(_ geometry: SketchEntityGeometry) -> [[SIMD2<Double>]] {
        switch geometry {
        case .point(let at):
            let p = at.simd
            return [
                [p - SIMD2(crossSize, 0), p + SIMD2(crossSize, 0)], [p - SIMD2(0, crossSize), p + SIMD2(0, crossSize)],
            ]
        case .line(let start, let end):
            return [[start.simd, end.simd]]
        case .circle(let center, let radius):
            return [arc(center.simd, radius, from: 0, sweep: 2 * .pi)]
        case .arc(let center, let radius, let start, let end):
            var sweep = (end - start).truncatingRemainder(dividingBy: 360)
            if sweep <= 0 { sweep += 360 }
            return [arc(center.simd, radius, from: start * .pi / 180, sweep: sweep * .pi / 180)]
        }
    }

    private static func arc(_ center: SIMD2<Double>, _ radius: Double, from: Double, sweep: Double) -> [SIMD2<Double>] {
        let count = max(2, Int((sweep / (.pi / 18)).rounded(.up)))
        return (0...count).map { index in
            let angle = from + sweep * Double(index) / Double(count)
            return center + radius * SIMD2(cos(angle), sin(angle))
        }
    }

    /// Every other `dash`-long piece of each segment; segments shorter than a dash alternate whole.
    private static func dashed(_ segments: [(SIMD2<Double>, SIMD2<Double>)]) -> [(SIMD2<Double>, SIMD2<Double>)] {
        var result: [(SIMD2<Double>, SIMD2<Double>)] = []
        for (index, (a, b)) in segments.enumerated() {
            let length = simd_distance(a, b)
            guard length > dash else {
                if index % 2 == 0 { result.append((a, b)) }
                continue
            }
            var offset = 0.0
            while offset < length - 1e-9 {
                let end = min(offset + dash, length)
                result.append((a + (b - a) * (offset / length), a + (b - a) * (end / length)))
                offset += 2 * dash
            }
        }
        return result
    }
}
