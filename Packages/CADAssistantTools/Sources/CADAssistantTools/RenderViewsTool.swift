import CADModel
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
        colour. Each view is framed on its own; its caption gives the mm per pixel. Use it to check the shape after \
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
                ])
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        do throws(ToolError) {
            let arguments = try Arguments(arguments, allowed: ["views"])
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
            let rendering = await session.renderViews(views)
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

public struct ViewRendering: Sendable {
    public let text: String
    public let views: [RenderedView]

    static let palette: [(name: String, colour: SIMD3<Float>)] = [
        ("blue", SIMD3(0.27, 0.48, 0.85)), ("orange", SIMD3(0.93, 0.55, 0.17)), ("green", SIMD3(0.33, 0.68, 0.32)),
        ("red", SIMD3(0.85, 0.27, 0.27)), ("purple", SIMD3(0.58, 0.40, 0.80)), ("teal", SIMD3(0.20, 0.66, 0.66)),
        ("yellow", SIMD3(0.90, 0.78, 0.20)), ("pink", SIMD3(0.90, 0.47, 0.70)),
    ]

    /// Renders every body of `result` that has a mesh, coloured from the palette in body order.
    static func render(_ result: RebuildResult, views: [ViewDirection]) -> ViewRendering {
        var shown: [String] = []
        var missing: [String] = []
        var bodies: [RenderBody] = []
        for part in result.parts {
            for body in part.bodies {
                let name = "\(body.name) (\(part.name))"
                guard let mesh = body.mesh, mesh.triangleCount > 0 else {
                    missing.append("\(name) (\(body.error ?? "no mesh"))")
                    continue
                }
                let colour = palette[bodies.count % palette.count]
                bodies.append(RenderBody(mesh: mesh, colour: colour.colour))
                shown.append("\(name) \(colour.name)")
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
    public func renderViews(_ views: [ViewDirection] = ViewDirection.allCases) async -> ViewRendering {
        guard let result = await currentResult() else {
            return ViewRendering(
                text: "The model could not be rebuilt; call get_listing to see the statuses.", views: [])
        }
        return ViewRendering.render(result, views: views)
    }
}
