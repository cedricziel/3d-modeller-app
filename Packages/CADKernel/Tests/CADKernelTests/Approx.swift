func approx(_ a: Double?, _ b: Double, tolerance: Double = 1e-6) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance * max(1, abs(b))
}

func approx(_ a: SIMD3<Double>, _ b: SIMD3<Double>, tolerance: Double = 1e-6) -> Bool {
    approx(a.x, b.x, tolerance: tolerance) && approx(a.y, b.y, tolerance: tolerance)
        && approx(a.z, b.z, tolerance: tolerance)
}
