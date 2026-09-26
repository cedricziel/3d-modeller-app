import CADModel
import Foundation
import SwiftUIAssistant

public struct ExportTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "export"

    public let description = """
        Writes the rebuilt model to a file in the export folder, in millimetres. step keeps exact geometry and, for \
        an assembly, its structure: each part once as a product, each instance placed where the joints put it, with \
        names and colours. stl (binary) and 3mf are triangle meshes for printing. Without part, body or instance it \
        exports the assembly when there are instances, else every part. path is relative to the export folder; the \
        extension is added when missing. An existing file is replaced only with overwrite: true.
        """

    public var parameters: [ToolParameter] {
        [
            .enumParameter(
                "format", description: "step, stl or 3mf.", values: ExportFormat.allCases.map(\.fileExtension)),
            .optionalString("part", description: "Export only this part (all its bodies)."),
            .optionalString("body", description: "Export only this body of the part, e.g. Body2."),
            .optionalString("instance", description: "Export only this instance, where the assembly places it."),
            .optionalString(
                "path", description: "File name inside the export folder; defaults to the target's name."),
            ToolParameter(
                name: "overwrite", type: .boolean, description: "Replace an existing file.", required: false),
            .optionalNumber(
                "tolerance",
                description: "Mesh formats only: the largest gap between the mesh and the surface, in mm (0.001…1); "
                    + "0.01 when omitted."),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        do throws(ToolError) {
            let request = try await session.exportRequest(arguments)
            guard let directory = await session.exportDirectory else {
                throw ToolError("This host grants no export folder, so export cannot write files here.")
            }
            let url: URL
            do {
                url = try ExportPath.resolve(
                    request.path, in: directory, format: request.format, overwrite: request.overwrite)
            } catch {
                throw ToolError(error.description)
            }
            do {
                let summary = try await session.export(
                    request.target, as: request.format, to: url, tolerance: request.tolerance)
                return .success(Self.describe(summary, in: directory))
            } catch {
                throw ToolError(error.description)
            }
        } catch {
            return .failure(error.description)
        }
    }

    static func describe(_ summary: ExportSummary, in directory: URL) -> String {
        let name = ExportPath.relative(summary.url, to: directory.resolvingSymlinksInPath())
        let size = ByteCountFormatter.string(fromByteCount: Int64(summary.bytes), countStyle: .file)
        var text = "Wrote \(name) (\(summary.format.displayName), \(size), mm) at \(summary.url.path): "
        text += "products \(summary.products.joined(separator: ", "))"
        if !summary.occurrences.isEmpty { text += "; occurrences \(summary.occurrences.joined(separator: ", "))" }
        text += "; \(summary.bodyCount) \(summary.bodyCount == 1 ? "body" : "bodies")"
        if let triangles = summary.triangleCount { text += ", \(triangles) triangles" }
        text += "."
        if !summary.skipped.isEmpty { text += " Skipped: \(summary.skipped.joined(separator: "; "))." }
        return text
    }
}

struct ExportToolRequest {
    let format: ExportFormat
    let target: ExportTarget
    let path: String
    let overwrite: Bool
    let tolerance: Double
}

extension CADSession {
    func exportRequest(_ raw: [String: JSONValue]) throws(ToolError) -> ExportToolRequest {
        let arguments = try Arguments(
            raw, allowed: ["format", "part", "body", "instance", "path", "overwrite", "tolerance"])
        let formatName = try arguments.requiredString("format")
        guard let format = ExportFormat(rawValue: formatName.lowercased()) else {
            throw ToolError("'format' is step, stl or 3mf, not '\(formatName)'.")
        }
        let part = try arguments.string("part")
        let body = try arguments.string("body")
        let instance = try arguments.string("instance")
        guard instance == nil || (part == nil && body == nil) else {
            throw ToolError("Give either instance or part (with body), not both.")
        }
        let target: ExportTarget
        let defaultName: String
        if let instance {
            let index = try document.instanceIndex(named: instance)
            target = .instance(document.instances[index].id)
            defaultName = instance
        } else if part != nil || body != nil {
            let index = try document.partIndex(named: part)
            let chosen = document.parts[index]
            if let body {
                target = .body(part: chosen.id, body: body)
                defaultName = "\(chosen.name)-\(body)"
            } else {
                target = .part(chosen.id)
                defaultName = chosen.name
            }
        } else {
            target = .document
            defaultName = "model"
        }
        var tolerance = ModelGeometry.defaultExportTolerance
        if let value = try arguments.scalar("tolerance") {
            guard case .number(let number) = value, (0.001...1).contains(number) else {
                throw ToolError("'tolerance' is a number of mm from 0.001 to 1.")
            }
            guard format.isMesh else { throw ToolError("'tolerance' applies to stl and 3mf only; STEP is exact.") }
            tolerance = number
        }
        return ExportToolRequest(
            format: format, target: target, path: try arguments.string("path") ?? defaultName,
            overwrite: try arguments.bool("overwrite") ?? false, tolerance: tolerance)
    }
}
