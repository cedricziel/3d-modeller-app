import Foundation

/// A sketch as the rebuild solved it.
public struct SketchResult: Sendable, Equatable, Identifiable {
    /// The sketch feature's id.
    public let id: UUID
    public let name: String
    public let frame: SketchFrame
    /// The solved entities, or the stored ones when the solve failed.
    public let entities: [SketchEntity]
    public let state: SketchSolveState
    public let degreesOfFreedom: Int
    public let profiles: SketchProfiles
}
