import AppKit
import CADAssistantTools
import CADModel
import SwiftUI
import UniformTypeIdentifiers

/// One thing File ▸ Export can write.
struct ExportScope: Hashable, Identifiable {
    let target: ExportTarget
    let label: String
    let suggestedName: String

    var id: String { label }

    func fileName(for format: ExportFormat) -> String {
        "\(suggestedName).\(format.fileExtension)"
    }

    static func choices(for document: CADDocument, result: RebuildResult?) -> [ExportScope] {
        let whole =
            document.instances.isEmpty
            ? ExportScope(target: .document, label: "All parts", suggestedName: "Model")
            : ExportScope(target: .document, label: "Whole assembly", suggestedName: "Assembly")
        var scopes = [whole]
        for part in document.parts {
            scopes.append(ExportScope(target: .part(part.id), label: "Part \(part.name)", suggestedName: part.name))
            let bodies = result?.parts.first { $0.id == part.id }?.bodies.map(\.name) ?? []
            guard bodies.count > 1 else { continue }
            for body in bodies {
                scopes.append(
                    ExportScope(
                        target: .body(part: part.id, body: body), label: "Body \(part.name)/\(body)",
                        suggestedName: "\(part.name)-\(body)"))
            }
        }
        for instance in document.instances {
            scopes.append(
                ExportScope(
                    target: .instance(instance.id), label: "Instance \(instance.name)", suggestedName: instance.name))
        }
        return scopes
    }
}

/// Picks the format and what to export, then asks where to save it.
struct ExportSheet: View {
    let session: CADSession
    let scopes: [ExportScope]
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .step
    @State private var scopeID: String?
    @State private var tolerance = ModelGeometry.defaultExportTolerance
    @State private var isExporting = false
    @State private var failure: String?

    var body: some View {
        Form {
            Picker("Format", selection: $format) {
                ForEach(ExportFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Export", selection: Binding(get: { scopeID ?? scopes.first?.id }, set: { scopeID = $0 })) {
                ForEach(scopes) { Text($0.label).tag(Optional($0.id)) }
            }
            if format.isMesh {
                TextField("Tolerance (mm)", value: $tolerance, format: .number)
            }
            if let failure {
                Text(failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Export…") { choosePlace() }
                    .disabled(isExporting || scopes.isEmpty || (format.isMesh && !(0.001...1).contains(tolerance)))
            }
        }
    }

    private var scope: ExportScope? {
        scopes.first { $0.id == (scopeID ?? scopes.first?.id) }
    }

    private func choosePlace() {
        guard let scope else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.nameFieldStringValue = scope.fileName(for: format)
        panel.canCreateDirectories = true
        let format = format
        let tolerance = tolerance
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await export(scope, format: format, tolerance: tolerance, to: url) }
        }
    }

    private func export(_ scope: ExportScope, format: ExportFormat, tolerance: Double, to url: URL) async {
        isExporting = true
        defer { isExporting = false }
        do {
            _ = try await session.export(scope.target, as: format, to: url, tolerance: tolerance)
            dismiss()
        } catch {
            failure = error.description
        }
    }
}
