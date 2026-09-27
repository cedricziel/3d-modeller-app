import CADModel
import Foundation

extension CADSession {
    /// Writes `target` of the current document to `url`, rebuilding first when needed. The kernel work runs off the
    /// main actor.
    public func export(
        _ target: ExportTarget, as format: ExportFormat, to url: URL,
        tolerance: Double = ModelGeometry.defaultExportTolerance
    ) async throws(ExportError) -> ExportSummary {
        _ = await currentResult()
        guard isResultCurrent, let result, let geometry else {
            throw ExportError("The model could not be rebuilt; call get_listing to see the statuses.")
        }
        return try await Self.export(geometry, target, result, format, url, tolerance)
    }

    @concurrent
    private static func export(
        _ geometry: ModelGeometry, _ target: ExportTarget, _ result: RebuildResult, _ format: ExportFormat,
        _ url: URL, _ tolerance: Double
    ) async throws(ExportError) -> ExportSummary {
        try geometry.export(target, of: result, as: format, to: url, tolerance: tolerance)
    }
}
