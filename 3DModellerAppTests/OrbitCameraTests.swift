import Foundation
import Testing
import simd
@testable import _D_Modeller

@Suite("OrbitCamera Tests")
struct OrbitCameraTests {

    @Test
    func testDefaultCameraLooksDownOnTheGround() {
        let camera = OrbitCamera()

        #expect(camera.position.y > 0)
        #expect(abs(simd_length(camera.position) - camera.distance) < 0.0001)
    }

    @Test
    func testDraggingUpRaisesTheCamera() {
        let camera = OrbitCamera()

        let orbited = camera.orbited(by: CGSize(width: 0, height: -50))

        #expect(orbited.position.y > camera.position.y)
    }

    @Test
    func testPitchStopsShortOfStraightDown() {
        let camera = OrbitCamera()

        let orbited = camera.orbited(by: CGSize(width: 0, height: -100_000))

        #expect(orbited.pitch < Float.pi / 2)
    }

    @Test
    func testZoomStaysWithinLimits() {
        let camera = OrbitCamera()

        #expect(camera.zoomed(by: 1000).distance == OrbitCamera.distanceRange.lowerBound)
        #expect(camera.zoomed(by: 0.001).distance == OrbitCamera.distanceRange.upperBound)
    }

    @Test
    func testFramingCentresOnTheBoundsAndBacksOffWithTheirSize() {
        let small = OrbitCamera.framing(min: SIMD3(-0.05, 0, -0.05), max: SIMD3(0.05, 0.02, 0.05))
        let large = OrbitCamera.framing(min: SIMD3(-1, 0, -1), max: SIMD3(1, 1, 1))
        #expect(simd_distance(small.target, SIMD3(0, 0.01, 0)) < 1e-6)
        #expect(small.distance < large.distance)
        #expect(OrbitCamera.distanceRange.contains(small.distance))
        #expect(simd_distance(small.position, small.target) - small.distance < 1e-4)
    }

    @Test
    func testFramingIgnoresMissingBounds() {
        #expect(OrbitCamera.framing(nil) == OrbitCamera())
    }
}
