import CADModel
import Foundation
import SwiftUIAssistant
import simd

public struct MeasureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "measure"

    public let description = """
        Measures the rebuilt model exactly (mm, mm², mm³, degrees). kind distance: the minimum distance between a and \
        b with the closest points (0 when they touch or overlap). kind angle: between two planar faces (their outward \
        normals, 0–180°), two straight edges (0–90°), or an edge and a planar face (edge to plane, 0–90°). kind size: \
        of a body its volume, surface area, bounds, extent and face and edge counts; of a face its type, area, centre, \
        normal or radius and bounds; of an edge its type, length and ends or radius. kind interference: the volume two \
        bodies share, or their clearance when they do not overlap. Each operand is {"body": "Body1"}, \
        {"body": "Body1", "face": "Plate.top"}, {"body": "Body1", "edge": "edge(Plate.front, Plate.top)"} or \
        {"point": [x, y, z]}; add "part" when the document has several parts. In an assembly, \
        {"instance": "Lid"} or {"instance": "Lid", "face": "Plate.top"} measures an instance where it is placed \
        (add "body" when its part has several); interference between two instances checks that they do not \
        overlap. A face or edge is a name or a filter that matches exactly one.
        """

    public var parameters: [ToolParameter] {
        let operand: [String: JSONValue] = [
            "type": "object",
            "properties": [
                "part": ["type": "string"], "instance": ["type": "string"], "body": ["type": "string"],
                "face": ["type": "string"],
                "edge": ["type": "string"],
                "point": ["type": "array", "items": .object(ToolSchemas.scalar), "minItems": 3, "maxItems": 3],
            ],
            "additionalProperties": false,
        ]
        return [
            .enumParameter("kind", description: "What to measure.", values: MeasureKind.allCases.map(\.rawValue)),
            .custom("a", description: "The first operand, or the only one for size.", required: true, schema: operand),
            .custom(
                "b", description: "The second operand, for distance, angle and interference.", required: false,
                schema: operand),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.measure(arguments)
    }
}

enum MeasureKind: String, CaseIterable {
    case distance, angle, size, interference
}

extension CADSession {
    func measure(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        do throws(ToolError) {
            let arguments = try Arguments(raw, allowed: ["kind", "a", "b"])
            let kindName = try arguments.requiredString("kind")
            guard let kind = MeasureKind(rawValue: kindName) else {
                throw ToolError("'kind' is distance, angle, size or interference, not '\(kindName)'.")
            }
            guard let a = raw["a"], !a.isNull else { throw ToolError("Missing required argument 'a'.") }
            let b = raw["b"].flatMap { $0.isNull ? nil : $0 }
            switch (kind, b) {
            case (.size, _?): throw ToolError("size measures one thing; drop 'b'.")
            case (.distance, nil), (.angle, nil), (.interference, nil): throw ToolError("\(kind.rawValue) needs 'b'.")
            default: break
            }
            guard let result = await currentResult(), isResultCurrent, let geometry else {
                throw ToolError("The model could not be rebuilt; call get_listing to see the statuses.")
            }
            let first = try measureOperand(a, "a", in: result)
            let second = try b.map { (value) throws(ToolError) in try measureOperand(value, "b", in: result) }
            return .success(try await Measurement.run(kind, first, second, geometry))
        } catch {
            return .failure(error.description)
        }
    }
}

enum Measurement {
    /// Kernel measurements can take a while (interference runs a boolean), so they run off the main actor.
    @concurrent
    static func run(_ kind: MeasureKind, _ a: MeasureOperand, _ b: MeasureOperand?, _ geometry: ModelGeometry)
        async throws(ToolError) -> String
    {
        switch (kind, b) {
        case (.size, _): try size(a, geometry)
        case (.distance, let b?): try distance(a, b, geometry)
        case (.angle, let b?): try angle(a, b)
        case (.interference, let b?): try interference(a, b, geometry)
        case (_, nil): throw ToolError("\(kind.rawValue) needs 'b'.")
        }
    }

    static func distance(_ a: MeasureOperand, _ b: MeasureOperand, _ geometry: ModelGeometry) throws(ToolError)
        -> String
    {
        let distance = try kernel { () throws(MeasureError) in try geometry.distance(a.target, b.target) }
        return "Distance \(Format.number(distance.distance)) mm between \(a.label) and \(b.label); closest points "
            + "\(Format.point(distance.pointA)) and \(Format.point(distance.pointB))"
    }

    static func angle(_ a: MeasureOperand, _ b: MeasureOperand) throws(ToolError) -> String {
        enum Direction {
            case normal(SIMD3<Double>)
            case line(SIMD3<Double>)
        }
        func direction(_ operand: MeasureOperand) throws(ToolError) -> Direction {
            let refusal = "angle takes planar faces and straight edges."
            switch operand.element {
            case .face(_, _, let face):
                guard let normal = face.normal else {
                    throw ToolError("\(operand.label) is a \(face.surface.rawValue) face; \(refusal)")
                }
                return .normal(simd_normalize(normal))
            case .edge(_, _, let edge):
                guard let line = edge.direction else {
                    throw ToolError("\(operand.label) is a \(edge.curve.rawValue) edge; \(refusal)")
                }
                return .line(simd_normalize(line))
            case .body: throw ToolError("\(operand.label) is a body; \(refusal)")
            case .point: throw ToolError("\(operand.label) is a point; \(refusal)")
            }
        }
        func degrees(_ radians: Double) -> String { Format.number(radians * 180 / .pi) + "°" }
        let clamp = { (value: Double) in min(1, max(-1, value)) }
        switch (try direction(a), try direction(b)) {
        case (.normal(let n), .normal(let m)):
            return "Angle between the normals of \(a.label) and \(b.label): \(degrees(acos(clamp(simd_dot(n, m)))))"
        case (.line(let d), .line(let e)):
            return "Angle between \(a.label) and \(b.label): \(degrees(acos(clamp(abs(simd_dot(d, e))))))"
        case (.line(let d), .normal(let n)):
            return "Angle between \(a.label) and the plane of \(b.label): \(degrees(asin(clamp(abs(simd_dot(d, n))))))"
        case (.normal(let n), .line(let d)):
            return "Angle between \(b.label) and the plane of \(a.label): \(degrees(asin(clamp(abs(simd_dot(d, n))))))"
        }
    }

    static func size(_ operand: MeasureOperand, _ geometry: ModelGeometry) throws(ToolError) -> String {
        switch operand.element {
        case .point:
            throw ToolError("A point has no size; measure a body, face or edge.")
        case .body(_, let body):
            guard let metrics = body.metrics else {
                throw ToolError("\(operand.label) could not be measured: \(body.error ?? "no metrics").")
            }
            var parts: [String] = []
            if let volume = metrics.volume { parts.append("volume \(Format.number(volume)) mm³") }
            if let topology = body.topology {
                parts.append("area \(Format.number(topology.faces.reduce(0) { $0 + $1.area })) mm²")
            }
            let extent = metrics.boundsMax - metrics.boundsMin
            parts.append("bounds \(Format.point(metrics.boundsMin)) to \(Format.point(metrics.boundsMax))")
            parts.append(
                "extent \(Format.number(extent.x)) × \(Format.number(extent.y)) × \(Format.number(extent.z))")
            parts.append(
                "\(metrics.faceCount) faces" + (body.topology.map { ", \($0.edges.count) edges" } ?? ""))
            return "\(operand.label): " + parts.joined(separator: ", ")
        case .face(_, _, let face):
            let bounds = try kernel { () throws(MeasureError) in try geometry.bounds(of: operand.target) }
            var parts = [
                face.surface.rawValue, "area \(Format.number(face.area)) mm²", "centre \(Format.point(face.centroid))",
            ]
            if let normal = face.normal { parts.append("normal \(Format.point(normal))") }
            if let axis = face.axis { parts.append("axis \(Format.point(axis))") }
            if let radius = face.radius { parts.append("r=\(Format.number(radius))") }
            parts.append("bounds \(Format.point(bounds.min)) to \(Format.point(bounds.max))")
            return "\(operand.label): " + parts.joined(separator: ", ")
        case .edge(_, _, let edge):
            var parts = [edge.curve.rawValue, "length \(Format.number(edge.length)) mm"]
            switch edge.curve {
            case .circle:
                if let radius = edge.radius { parts.append("r=\(Format.number(radius))") }
                if let center = edge.center { parts.append("centre \(Format.point(center))") }
            case .line, .other:
                parts.append("from \(Format.point(edge.start)) to \(Format.point(edge.end))")
            }
            return "\(operand.label): " + parts.joined(separator: ", ")
        }
    }

    static func interference(_ a: MeasureOperand, _ b: MeasureOperand, _ geometry: ModelGeometry) throws(ToolError)
        -> String
    {
        guard case .body(let first, _) = a.element, case .body(let second, _) = b.element else {
            throw ToolError(
                "interference compares two bodies; give 'a' and 'b' as {\"body\": …} or {\"instance\": …} "
                    + "without a face, edge or point.")
        }
        let clearance = try kernel { () throws(MeasureError) in try geometry.distance(a.target, b.target) }.distance
        if Format.number(clearance) != "0" {
            return "\(a.label) and \(b.label) do not overlap; clearance \(Format.number(clearance)) mm"
        }
        let overlap = try kernel { () throws(MeasureError) in try geometry.interference(first, second) }
        if overlap > 0 { return "\(a.label) and \(b.label) overlap by \(Format.number(overlap)) mm³" }
        return "\(a.label) and \(b.label) touch without overlapping"
    }

    private static func kernel<T>(_ call: () throws(MeasureError) -> T) throws(ToolError) -> T {
        do { return try call() } catch { throw ToolError("The kernel could not measure this: \(error.description).") }
    }
}
