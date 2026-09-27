import CADModel
import Foundation

/// What the viewport draws: each part's own bodies at the origin, or the assembly's placed instances.
enum ViewportContent: String, CaseIterable, Identifiable {
    case parts
    case assembly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .parts: "Parts"
        case .assembly: "Assembly"
        }
    }

    static func automatic(for document: CADDocument) -> ViewportContent {
        document.instances.isEmpty ? .parts : .assembly
    }

    /// The content that shows the selection: a feature's part, or the assembly for an instance or a joint.
    static func following(selection: UUID?, in document: CADDocument) -> ViewportContent? {
        guard let selection else { return nil }
        if document.instances.contains(where: { $0.id == selection }) { return .assembly }
        if document.joints.contains(where: { $0.id == selection }) { return .assembly }
        if document.feature(id: selection) != nil { return .parts }
        return nil
    }
}

struct DisplayBody: Equatable {
    let name: String
    let mesh: BodyMesh
    let metrics: BodyMetrics?
    var appearance: Appearance?
}

extension RebuildResult {
    /// The meshes the content shows, each named after its body or instance.
    func displayBodies(_ content: ViewportContent) -> [DisplayBody] {
        let bodies: [(String, BodyResult, Appearance?)] =
            switch content {
            case .parts: parts.flatMap { part in part.bodies.map { ($0.name, $0, part.appearance) } }
            case .assembly:
                (assembly?.instances ?? []).flatMap { instance in
                    instance.bodies.map {
                        (
                            instance.bodies.count > 1 ? "\(instance.name)/\($0.name)" : instance.name, $0,
                            instance.appearance
                        )
                    }
                }
            }
        return bodies.compactMap { name, body, appearance in
            guard let mesh = body.mesh, mesh.triangleCount > 0 else { return nil }
            return DisplayBody(name: name, mesh: mesh, metrics: body.metrics, appearance: appearance)
        }
    }
}
