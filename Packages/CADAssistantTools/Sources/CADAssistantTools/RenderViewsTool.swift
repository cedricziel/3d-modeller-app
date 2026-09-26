import CADModel
import Foundation
import SwiftUIAssistant

public struct RenderViewsTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "render_views"

    public let description = """
        Renders the rebuilt model and returns the pictures: iso (seen from +X −Y +Z), top (down −Z), front (the −Y \
        side) and right (the +X side), each 512 × 512 px, flat shaded with dark feature edges, each body in its own \
        colour. When the document has instances it shows the assembly, each instance in its own colour; show: parts \
        shows the parts' own bodies instead. Each view is framed on its own; its caption gives the mm per pixel. Use it to check the shape after \
        bigger changes; it costs about 350 input tokens per view, now and on every later turn, so ask only for the \
        views you need.
        """

    public var parameters: [ToolParameter] {
        [
            .custom(
                "views", description: "Views to render; all four when omitted.", required: false,
                schema: [
                    "type": "array",
                    "items": ["type": "string", "enum": .array(ViewDirection.allCases.map { .string($0.rawValue) })],
                ]),
            .enumParameter(
                "show", description: "assembly (the default when there are instances) or parts.",
                values: RenderContent.allCases.map(\.rawValue), required: false),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        do throws(ToolError) {
            let arguments = try Arguments(arguments, allowed: ["views", "show"])
            let content = try arguments.string("show").map { (name) throws(ToolError) in
                guard let content = RenderContent(rawValue: name) else {
                    throw ToolError("'show' is parts or assembly, not '\(name)'.")
                }
                return content
            }
            if content == .assembly, await session.document.instances.isEmpty {
                throw ToolError("The document has no instances to show; use show: parts.")
            }
            let names = try arguments.strings("views", "view names") ?? ViewDirection.allCases.map(\.rawValue)
            var views: [ViewDirection] = []
            for name in names {
                guard let view = ViewDirection(rawValue: name) else {
                    let known = ViewDirection.allCases.map(\.rawValue).joined(separator: ", ")
                    throw ToolError("Unknown view '\(name)'. Views: \(known).")
                }
                if !views.contains(view) { views.append(view) }
            }
            guard !views.isEmpty else { throw ToolError("'views' is empty; omit it for all four views.") }
            let rendering = await session.renderViews(views, show: content)
            return .success(
                rendering.text,
                images: rendering.views.map {
                    ToolImage(
                        data: $0.png,
                        caption: "\($0.view.caption), \(Format.number($0.millimetresPerPixel)) mm per pixel")
                })
        } catch {
            return .failure(error.description)
        }
    }
}

public enum RenderContent: String, Sendable, CaseIterable {
    case parts, assembly
}

public struct ViewRendering: Sendable {
    public let text: String
    public let views: [RenderedView]

    static let palette: [(name: String, colour: SIMD3<Float>)] = ExportPalette.colors.map {
        ($0.name, SIMD3<Float>($0.rgb))
    }

    @concurrent
    static func renderOffMain(
        _ result: RebuildResult, views: [ViewDirection], content: RenderContent, partNames: [UUID: String]
    ) async -> ViewRendering {
        render(result, views: views, content: content, partNames: partNames)
    }

    /// The assembly's instances or the parts' bodies that have a mesh, coloured from the palette in order.
    static func render(
        _ result: RebuildResult, views: [ViewDirection], content: RenderContent = .parts,
        partNames: [UUID: String] = [:]
    ) -> ViewRendering {
        var shown: [String] = []
        var missing: [String] = []
        var bodies: [RenderBody] = []
        func add(_ name: String, _ meshes: [BodyMesh], problem: String?) {
            let usable = meshes.filter { $0.triangleCount > 0 }
            guard !usable.isEmpty, problem == nil else {
                missing.append("\(name) (\(problem ?? "no mesh"))")
                return
            }
            let colour = palette[shown.count % palette.count]
            bodies += usable.map { RenderBody(mesh: $0, colour: colour.colour) }
            shown.append("\(name) \(colour.name)")
        }
        switch content {
        case .parts:
            for part in result.parts {
                for body in part.bodies {
                    add(
                        "\(body.name) (\(part.name))", body.mesh.map { [$0] } ?? [],
                        problem: body.mesh == nil ? (body.error ?? "no mesh") : nil)
                }
            }
        case .assembly:
            for instance in result.assembly?.instances ?? [] {
                let name = "\(instance.name) (\(partNames[instance.part] ?? "missing part"))"
                if case .failed(let reason) = instance.status {
                    add(name, [], problem: reason)
                } else {
                    add(name, instance.bodies.compactMap(\.mesh), problem: nil)
                }
            }
        }
        let notShown = missing.isEmpty ? "" : " Not shown: \(missing.joined(separator: ", "))."
        guard !bodies.isEmpty else {
            let text = missing.isEmpty ? "Nothing to render: the model has no bodies." : "Nothing to render." + notShown
            return ViewRendering(text: text, views: [])
        }
        let rendered = ViewRenderer.render(bodies, views: views)
        let count = rendered.count == 1 ? "1 view" : "\(rendered.count) views"
        return ViewRendering(
            text: "Rendered \(count), \(ViewRenderer.size) × \(ViewRenderer.size) px each: "
                + "\(shown.joined(separator: ", ")). Lengths in mm.\(notShown)",
            views: rendered)
    }
}

extension CADSession {
    /// Pictures of the current document's bodies, rebuilding first when needed.
    /// Without `show`, the assembly when an instance has a mesh, else the parts.
    public func renderViews(_ views: [ViewDirection] = ViewDirection.allCases, show: RenderContent? = nil) async
        -> ViewRendering
    {
        guard let result = await currentResult() else {
            return ViewRendering(
                text: "The model could not be rebuilt; call get_listing to see the statuses.", views: [])
        }
        let hasInstanceMeshes = (result.assembly?.instances ?? []).contains { instance in
            instance.bodies.contains { ($0.mesh?.triangleCount ?? 0) > 0 }
        }
        let content = show ?? (hasInstanceMeshes ? .assembly : .parts)
        let partNames = Dictionary(document.parts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return await ViewRendering.renderOffMain(result, views: views, content: content, partNames: partNames)
    }
}
