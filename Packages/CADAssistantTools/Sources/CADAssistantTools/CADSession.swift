import CADModel
import Foundation
import Observation
import SwiftUIAssistant
import Synchronization

/// Owns a document and its latest rebuild so the assistant tools can edit and inspect it without any UI.
/// A host that keeps its own copy of the document (for files and undo) sets `onCommit` and calls `load` when its
/// copy changes for other reasons.
@MainActor
@Observable
public final class CADSession {
    public private(set) var document: CADDocument
    /// The latest rebuild; it may lag behind `document` while a rebuild runs.
    public private(set) var result: RebuildResult?

    /// Called with every document an edit produces and the edit's action name, before the rebuild.
    @ObservationIgnored public var onCommit: (@MainActor (CADDocument, String) -> Void)?

    /// Measurements on the bodies of `result`.
    @ObservationIgnored public private(set) var geometry: ModelGeometry?

    @ObservationIgnored private let build: @Sendable (CADDocument) async throws -> RebuiltModel
    @ObservationIgnored private var builtDocument: CADDocument?
    /// The running rebuild. Callers share it, and their own cancellation does not stop it; only a rebuild of a
    /// newer document cancels it, so a view that disappears mid-rebuild cannot leave the document unbuilt.
    @ObservationIgnored private var building: (document: CADDocument, task: Task<RebuiltModel, any Error>)?
    private nonisolated let snapshot: Mutex<String>

    /// Without a sketch solver, sketches fail to build and the features that use them are skipped. Without an
    /// assembly solver, every joint fails.
    public init<Kernel: GeometryKernel>(
        document: CADDocument = CADDocument(), kernel: Kernel, sketchSolver: (any SketchSolving)? = nil,
        assemblySolver: (any AssemblySolving)? = nil
    ) {
        let engine = RebuildEngine(kernel: kernel, sketchSolver: sketchSolver, assemblySolver: assemblySolver)
        build = { try await engine.build($0) }
        self.document = document
        snapshot = Mutex(DocumentListing.render(document, result: nil))
    }

    /// The listing of the document, with statuses only from a rebuild of this exact document.
    public var listing: String {
        DocumentListing.render(document, result: builtDocument == document ? result : nil)
    }

    /// The latest listing, readable from any isolation, for the assistant's context provider.
    public nonisolated func currentListing() -> String {
        snapshot.withLock { $0 }
    }

    public nonisolated func assistantContext() -> ListingContext {
        ListingContext(listing: currentListing())
    }

    @discardableResult
    public func rebuild() async throws -> RebuildResult {
        let target = document
        let task: Task<RebuiltModel, any Error>
        if let building, building.document == target {
            task = building.task
        } else {
            building?.task.cancel()
            let build = build
            task = Task { try await build(target) }
            building = (target, task)
        }
        defer { if building?.task == task { building = nil } }
        let rebuilt = try await task.value
        if document == target {
            result = rebuilt.result
            geometry = rebuilt.geometry
            builtDocument = target
            publishListing()
        }
        return rebuilt.result
    }

    /// Builds `document` off the main actor without adopting it, for previews that must not edit the document.
    public func preview(_ document: CADDocument) async throws -> RebuildResult {
        let build = build
        return try await build(document).result
    }

    /// Takes over a document the host changed, at once and without rebuilding, so an edit computed right after
    /// starts from it. Follow with `load` to rebuild.
    public func adopt(_ document: CADDocument) {
        guard document != self.document else { return }
        self.document = document
        publishListing()
    }

    /// Adopts a document changed outside the tools (opened, undone, edited in the UI) and rebuilds it.
    public func load(_ document: CADDocument) async {
        adopt(document)
        if builtDocument == document || building?.document == document { return }
        _ = try? await rebuild()
    }

    /// Replaces the document with an edited one, reports it through `onCommit` and rebuilds it.
    /// Returns the rebuild of `document`, even when a newer document replaced it meanwhile.
    @discardableResult
    public func apply(_ document: CADDocument, actionName: String) async -> RebuildResult? {
        self.document = document
        publishListing()
        onCommit?(document, actionName)
        return try? await rebuild()
    }

    /// Whether `result` is a rebuild of the current document.
    public var isResultCurrent: Bool { builtDocument == document }

    /// The rebuild of the current document, rebuilding first when the latest result is for another document.
    public func currentResult() async -> RebuildResult? {
        if builtDocument == document { return result }
        return try? await rebuild()
    }

    private func publishListing() {
        let text = listing
        snapshot.withLock { $0 = text }
    }
}

public struct ListingContext: AssistantContext {
    public let listing: String

    public init(listing: String) {
        self.listing = listing
    }

    public var contextDescription: String {
        "Current model (lengths in mm, angles in degrees):\n\(listing)"
    }
}
