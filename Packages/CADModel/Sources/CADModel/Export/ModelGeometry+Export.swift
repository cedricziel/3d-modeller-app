import Foundation

struct ExportRequest: Sendable {
    let target: ExportTarget
    let result: RebuildResult
    let format: ExportFormat
    let url: URL
    let tolerance: Double
}

extension ModelGeometry {
    public static let defaultExportTolerance = 0.01

    /// Writes `target` from the bodies of `result` to `url`. Mesh formats tessellate each body with a linear
    /// deflection of at most `tolerance` mm.
    public func export(
        _ target: ExportTarget, of result: RebuildResult, as format: ExportFormat, to url: URL,
        tolerance: Double = defaultExportTolerance
    ) throws(ExportError) -> ExportSummary {
        guard tolerance.isFinite, tolerance > 0 else { throw ExportError("The tolerance must be above 0 mm") }
        return try exporter(
            ExportRequest(target: target, result: result, format: format, url: url, tolerance: tolerance))
    }
}

struct ModelExporter<Kernel: GeometryKernel>: Sendable {
    let kernel: Kernel
    let bodies: [BodyKey: Kernel.Body]

    func export(_ request: ExportRequest) throws(ExportError) -> ExportSummary {
        let plan = try ExportPlan.scene(request.target, in: request.result, built: Set(bodies.keys))
        let triangles: Int?
        switch request.format {
        case .step:
            let scene = try plan.map { (key) throws(ExportError) in try body(key) }
            try kernelCall("write \(request.url.lastPathComponent)") { try kernel.writeSTEP(scene, to: request.url) }
            triangles = nil
        case .stl, .threeMF:
            let scene = try plan.map { (key) throws(ExportError) in try mesh(key, tolerance: request.tolerance) }
            let data =
                request.format == .stl
                ? STLWriter.data(scene.placedBodies.map { $0.body.transformed(by: $0.transform) })
                : ThreeMFWriter.data(scene)
            try kernelCall("write \(request.url.lastPathComponent)") {
                try data.write(to: request.url, options: .atomic)
            }
            triangles = scene.placedBodies.reduce(0) { $0 + $1.body.triangleCount }
        }
        let bytes = (try? request.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ExportSummary(
            format: request.format, url: request.url, bytes: bytes, products: plan.products.map(\.name),
            occurrences: plan.occurrences.map(\.name), bodyCount: plan.placedBodies.count, triangleCount: triangles,
            skipped: plan.skipped)
    }

    private func body(_ key: BodyKey) throws(ExportError) -> Kernel.Body {
        guard let body = bodies[key] else { throw ExportError("\(key.body) was not built") }
        return body
    }

    private func mesh(_ key: BodyKey, tolerance: Double) throws(ExportError) -> BodyMesh {
        let body = try body(key)
        let mesh = try kernelCall("tessellate \(key.body)") { try kernel.mesh(of: body, tolerance: tolerance) }
        guard mesh.triangleCount > 0 else { throw ExportError("\(key.body) has no triangles") }
        return mesh
    }

    private func kernelCall<T>(_ action: String, _ call: () throws -> T) throws(ExportError) -> T {
        do { return try call() } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError("Could not \(action): \(error)")
        }
    }
}
