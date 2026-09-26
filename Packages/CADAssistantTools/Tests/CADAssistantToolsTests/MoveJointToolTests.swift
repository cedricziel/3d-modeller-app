@testable import CADAssistantTools
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@MainActor
@Suite("move_joint, joint limits and motion in the listing")
struct MoveJointToolTests {
    /// A grounded box (Base) and a lid (Top) joined by the revolute "Hinge" on the box's top face, limited to 0…110°.
    private func hinged() async throws -> Harness {
        let harness = Harness(CADDocument(parts: [Part(name: "Box"), Part(name: "Lid")]))
        _ = try await harness.call(
            "add_feature", ["part": "Box", "name": "Shell", "type": "box", "width": 60, "depth": 40, "height": 30]
        )
        _ = try await harness.call(
            "add_feature", ["part": "Lid", "name": "Cap", "type": "box", "width": 60, "depth": 40, "height": 5]
        )
        _ = try await harness.call("add_instance", ["part": "Box", "name": "Base", "grounded": true])
        _ = try await harness.call("add_instance", ["part": "Lid", "name": "Top"])
        let added = try await harness.call(
            "add_joint",
            [
                "kind": "revolute", "name": "Hinge", "a": ["instance": "Base", "face": "Shell.top"],
                "b": ["instance": "Top", "face": "Cap.bottom"], "limits": ["min": 0, "max": 110],
            ]
        )
        #expect(added.success, "\(added.message)")
        return harness
    }

    @Test("move_joint drives the joint in one undo step and reports where it is")
    func moveSetsValue() async throws {
        let harness = try await hinged()

        let result = try await harness.call("move_joint", ["joint": "Hinge", "value": 90])

        #expect(result.success)
        #expect(harness.document.joints.first?.value == 90)
        #expect(harness.commits.last == "Move Hinge")
        #expect(result.message.hasPrefix("Moved Hinge to 90°"))
        #expect(result.message.contains("Hinge: ok, at 90° driven, limits 0°…110°, 0 dof"))
    }

    @Test("move_joint refuses values outside the limits, joints without one motion, and unclear requests")
    func moveRefusals() async throws {
        let harness = try await hinged()
        _ = try await harness.call(
            "add_joint",
            [
                "kind": "fixed", "name": "Weld", "a": ["instance": "Base", "face": "Shell.front"],
                "b": ["instance": "Top", "face": "Cap.back"],
            ]
        )

        #expect(
            try await harness.refused("move_joint", ["joint": "Hinge", "value": 120])
                == "Hinge moves within 0°…110°; 120° is outside."
        )
        #expect(
            try await harness.refused("move_joint", ["joint": "Weld", "value": 1])
                == "Weld is a fixed joint, which has no single motion; only revolute, slider and cylindrical joints move."
        )
        #expect(
            try await harness.refused("move_joint", ["joint": "Hinge"])
                == "Give either value or free: true."
        )
        #expect(
            try await harness.refused("move_joint", ["joint": "Hinge", "value": 5, "free": true])
                == "Give either value or free: true."
        )
        #expect(
            try await harness.refused("move_joint", ["joint": "Nope", "value": 5])
                == "No joint named 'Nope'. Joints: Hinge, Weld."
        )
        let expression = try await harness.refused("move_joint", ["joint": "Hinge", "value": "missing + 1"])
        #expect(expression?.contains("missing") == true)
    }

    @Test("free: true releases the drive")
    func freeReleases() async throws {
        let harness = try await hinged()
        _ = try await harness.call("move_joint", ["joint": "Hinge", "value": 30])

        let result = try await harness.call("move_joint", ["joint": "Hinge", "free": true])

        #expect(result.success)
        #expect(harness.document.joints.first?.value == nil)
        #expect(result.message.hasPrefix("Released Hinge"))
        #expect(result.message.contains("Hinge: ok, at 0° free, limits 0°…110°, 1 dof"))
    }

    @Test("add_joint takes limits and a value, and refuses them where they cannot apply")
    func addJointWithLimits() async throws {
        let harness = try await hinged()
        let limits = try #require(harness.document.joints.first?.limits)

        #expect(limits == JointLimits(min: 0, max: 110))
        #expect(
            try await harness.refused(
                "add_joint",
                [
                    "kind": "ball", "a": ["instance": "Base", "face": "Shell.top"],
                    "b": ["instance": "Top", "face": "Cap.bottom"], "limits": ["max": 5],
                ]
            ) == "Ball1: a ball joint has no single motion to limit; remove its limits"
        )
        #expect(
            try await harness.refused(
                "add_joint",
                [
                    "kind": "slider", "a": ["instance": "Base", "face": "Shell.top"],
                    "b": ["instance": "Top", "face": "Cap.bottom"], "limits": ["min": 0, "max": 10], "value": 20,
                ]
            ) == "Slider1: value 20 mm is outside its limits 0 mm…10 mm"
        )
    }

    @Test("edit_joint replaces or clears limits, refusing ones that exclude the current value")
    func editLimits() async throws {
        let harness = try await hinged()
        _ = try await harness.call("move_joint", ["joint": "Hinge", "value": 90])

        #expect(
            try await harness.refused("edit_joint", ["joint": "Hinge", "limits": ["min": 0, "max": 45]])
                == "Hinge: value 90° is outside its limits 0°…45°"
        )
        let cleared = try await harness.call("edit_joint", ["joint": "Hinge", "limits": [:]])

        #expect(cleared.success)
        #expect(harness.document.joints.first?.limits == nil)
    }

    @Test("Changing a driven joint's kind drops a value and limits that no longer fit")
    func kindChangeDropsDrive() async throws {
        let harness = try await hinged()
        _ = try await harness.call("move_joint", ["joint": "Hinge", "value": 90])

        let result = try await harness.call("edit_joint", ["joint": "Hinge", "kind": "slider"])
        let joint = try #require(harness.document.joints.first)

        #expect(result.success)
        #expect(joint.value == nil)
        #expect(joint.limits == nil)
        #expect(result.message.hasPrefix("Edited joint Hinge; dropped its value and limits (they were in degrees)"))
    }

    @Test("The listing shows each joint's value, limits and freedoms, and each instance's freedoms")
    func listing() async throws {
        let harness = try await hinged()
        let free = harness.session.listing
        _ = try await harness.call("move_joint", ["joint": "Hinge", "value": 90])
        let driven = harness.session.listing

        #expect(
            free.contains("    Hinge  revolute Base Shell.top ↔ Top Cap.bottom, at 0° free, limits 0°…110°, 1 dof  ok"))
        #expect(free.contains("  Top  Lid at origin → solved (0, 0, 30)  ok, 1 dof free"))
        #expect(
            driven.contains("Hinge  revolute Base Shell.top ↔ Top Cap.bottom, at 90° driven, limits 0°…110°, 0 dof  ok")
        )
        #expect(driven.contains("ok, fully constrained"))
    }

    @Test("A preview builds a document without changing the session")
    func previewLeavesSession() async throws {
        let harness = try await hinged()
        let before = harness.session.result
        var moved = harness.document
        moved.assembly?.joints[0].value = 45

        let preview = try await harness.session.preview(moved)

        #expect(preview.assembly?.joints.first?.value == 45)
        #expect(harness.session.result == before)
        #expect(harness.document.joints.first?.value == nil)
    }
}
