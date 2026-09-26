import CADModel
import SwiftUI

struct ModelStatisticsView: View {
    let result: RebuildResult?

    var body: some View {
        HStack(spacing: 16) {
            if let result {
                Label("\(result.bodies.count) bodies", systemImage: "cube")
                Label("\(result.triangleCount) triangles", systemImage: "triangle")
                if result.failedFeatureCount > 0 {
                    Label("\(result.failedFeatureCount) failed", systemImage: "xmark.octagon").foregroundStyle(.red)
                }
            } else {
                Label("Rebuilding…", systemImage: "hourglass")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}
