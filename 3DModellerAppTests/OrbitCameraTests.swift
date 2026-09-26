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
}
