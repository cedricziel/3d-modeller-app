import CPlaneGCS

/// Owns one PlaneGCS system through the C shim; not shared across threads.
final class PlaneGCSSystem {
    struct Report {
        let solved: Bool
        let dof: Int
        let conflictingTags: [Int]
        let redundantTags: [Int]
    }

    private let handle: OpaquePointer

    init() throws(SketchSolverError) {
        guard let handle = pgs_create() else { throw .solverFailure("could not create a PlaneGCS system") }
        self.handle = handle
    }

    deinit {
        pgs_destroy(handle)
    }

    func add(_ geometry: SketchGeometry) throws(SketchSolverError) {
        let result =
            switch geometry {
            case .point(let p): pgs_add_point(handle, p.x, p.y)
            case .line(let start, let end): pgs_add_line(handle, start.x, start.y, end.x, end.y)
            case .circle(let center, let radius): pgs_add_circle(handle, center.x, center.y, radius)
            case .arc(let center, let radius, let startAngle, let endAngle):
                pgs_add_arc(handle, center.x, center.y, radius, startAngle, endAngle)
            }
        try check(result)
    }

    func add(_ constraint: PGSConstraint, tag: Int) throws(SketchSolverError) {
        try check(pgs_add_constraint(handle, Int32(tag), constraint))
    }

    func solve() throws(SketchSolverError) -> Report {
        var report = PGSReport()
        try check(pgs_solve(handle, &report))
        return Report(
            solved: report.solved != 0,
            dof: Int(report.dof),
            conflictingTags: tags(count: report.conflictingCount, pgs_conflicting),
            redundantTags: tags(count: report.redundantCount, pgs_redundant)
        )
    }

    func values(ofEntity index: Int) throws(SketchSolverError) -> [Double] {
        var values = [Double](repeating: 0, count: 5)
        let count = pgs_entity_values(handle, Int32(index), &values, Int32(values.count))
        try check(count)
        return Array(values.prefix(Int(count)))
    }

    private func tags(
        count: Int32, _ read: (OpaquePointer, UnsafeMutablePointer<Int32>, Int32) -> Int32
    ) -> [Int] {
        guard count > 0 else { return [] }
        var tags = [Int32](repeating: 0, count: Int(count))
        let copied = read(handle, &tags, count)
        return tags.prefix(Int(copied)).map(Int.init)
    }

    private func check(_ result: Int32) throws(SketchSolverError) {
        guard result < 0 else { return }
        throw .solverFailure(String(cString: pgs_last_error(handle)))
    }
}
