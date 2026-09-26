@testable import CADAssistantTools
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@MainActor
@Suite("add_joint, edit_joint, delete_joint")
struct JointToolTests {
    /// A grounded box 60 × 40 × 30 (Base) and a lid 60 × 40 × 5 (Top) at the origin, not joined yet.
    private func boxAndLid() async throws -> Harness {
        let harness = Harness(CADDocument(parts: [Part(name: "Box"), Part(name: "Lid")]))
        _ = try await harness.call(
            "add_feature", ["part": "Box", "name": "Shell", "type": "box", "width": 60, "depth": 40, "height": 30])
        _ = try await harness.call(
            "add_feature", ["part": "Lid", "name": "Cap", "type": "box", "width": 60, "depth": 40, "height": 5])
        _ = try await harness.call("add_instance", ["part": "Box", "name": "Base", "grounded": true])
        _ = try await harness.call("add_instance", ["part": "Lid", "name": "Top"])
        return harness
    }

    private let mate: [String: JSONValue] = [
        "kind": "fixed", "a": ["instance": "Base", "face": "Shell.top"],
        "b": ["instance": "Top", "face": "Cap.bottom"],
    ]

    @Test("A joint gets a default name, one undo step, and reports what it moved")
    func addJointDefaults() async throws {
        let harness = try await boxAndLid()

        let result = try await harness.call("add_joint", mate)
        let joint = try #require(harness.document.joints.first)

        #expect(result.success)
        #expect(joint.name == "Fixed1")
        #expect(joint.a.face == .name("Shell.top"))
        #expect(harness.commits.last == "Add joint Fixed1")
        #expect(result.message.contains("Fixed1: ok"))
        #expect(result.message.contains("Moved by joints: Top (0, 0, 0) → (0, 0, 30)"))
        #expect(result.message.contains("+ Fixed1  fixed Base Shell.top ↔ Top Cap.bottom  ok"))
        #expect(harness.document.instances[1].placement == .identity)
    }

    @Test("Joints are refused for unknown kinds, instances and faces, one instance twice, and bad names")
    func addJointRefusals() async throws {
        let harness = try await boxAndLid()
        _ = try await harness.call("add_joint", mate)
        func with(_ key: String, _ value: JSONValue) -> [String: JSONValue] {
            var arguments = mate
            arguments[key] = value
            return arguments
        }

        #expect(
            try await harness.refused("add_joint", with("kind", "weld"))
                == "Unknown joint kind 'weld'. Kinds: fixed, revolute, slider, cylindrical, ball, planar.")
        #expect(
            try await harness.refused("add_joint", with("a", ["instance": "Nope", "face": "Shell.top"]))
                == "a: No instance named 'Nope'. Instances: Base, Top.")
        #expect(
            try await harness.refused("add_joint", with("b", ["instance": "Base", "face": "Shell.bottom"]))
                == "Both sides are on Base; a joint joins two instances.")
        let face = try await harness.refused("add_joint", with("b", ["instance": "Top", "face": "Cap.nope"]))
        #expect(face?.hasPrefix("b: ") == true)
        #expect(face?.contains("Cap.nope") == true)
        #expect(
            try await harness.refused("add_joint", with("name", "Fixed1")) == "A joint named Fixed1 already exists.")
        #expect(
            try await harness.refused("add_joint", with("name", "a b"))
                == "'a b' is not a valid joint name: use letters, digits and _, starting with a letter or _.")
        let offset = try await harness.refused(
            "add_joint", with("a", ["instance": "Base", "face": "Shell.top", "offset": ["z": "missing + 1"]]))
        #expect(offset?.contains("Fixed2.a.offset.z = missing + 1") == true)
    }

    @Test("edit_joint replaces a side, flips, renames; with nothing to change it refuses")
    func editJoint() async throws {
        let harness = try await boxAndLid()
        _ = try await harness.call("add_joint", mate)

        let edited = try await harness.call(
            "edit_joint",
            [
                "joint": "Fixed1", "kind": "planar",
                "a": ["instance": "Base", "face": "Shell.top", "offset": ["z": 2]],
                "new_name": "Rest",
            ])
        let joint = try #require(harness.document.joints.first)

        #expect(edited.success)
        #expect(joint.name == "Rest")
        #expect(joint.kind == .planar)
        #expect(joint.a.offset == JointOffset(z: 2))
        #expect(joint.b.face == .name("Cap.bottom"))
        #expect(harness.commits.last == "Edit Fixed1")
        #expect(
            try await harness.refused("edit_joint", ["joint": "Rest"])
                == "Give at least one of kind, a, b, flip, limits, new_name.")
        #expect(
            try await harness.refused("edit_joint", ["joint": "Nope", "flip": true])
                == "No joint named 'Nope'. Joints: Rest.")
    }

    @Test("delete_joint removes the joint and the instance returns to its placement")
    func deleteJoint() async throws {
        let harness = try await boxAndLid()
        _ = try await harness.call("add_joint", mate)

        let result = try await harness.call("delete_joint", ["joint": "Fixed1"])

        #expect(harness.document.joints.isEmpty)
        #expect(harness.commits.last == "Delete joint Fixed1")
        #expect(result.message.contains("Moved by joints: Top (0, 0, 30) → (0, 0, 0)"))
    }

    @Test("Deleting an instance removes the joints that use it")
    func deleteInstanceRemovesJoints() async throws {
        let harness = try await boxAndLid()
        _ = try await harness.call("add_joint", mate)

        let result = try await harness.call("delete_instance", ["instance": "Top"])

        #expect(harness.document.joints.isEmpty)
        #expect(result.message.hasPrefix("Deleted instance Top; removed joints Fixed1"))
    }

    @Test("Renaming a feature rewrites the joint references on instances of its part only")
    func renameFeatureRewritesJoints() async throws {
        let harness = try await boxAndLid()
        _ = try await harness.call("add_joint", mate)

        let result = try await harness.call("rename_feature", ["feature": "Shell", "new_name": "Hull", "part": "Box"])
        let joint = try #require(harness.document.joints.first)

        #expect(joint.a.face == .name("Hull.top"))
        #expect(joint.b.face == .name("Cap.bottom"))
        #expect(result.message.contains("Fixed1 now refers to Hull.top (was Shell.top)"))
        #expect(harness.session.result?.assembly?.joints.first?.status == .ok)
    }

    @Test("The listing shows joints and where the solver put an instance")
    func listing() async throws {
        let harness = try await boxAndLid()
        _ = try await harness.call("add_joint", mate)
        let listing = harness.session.listing

        #expect(listing.contains("  Top  Lid at origin → solved (0, 0, 30)  ok"))
        #expect(listing.contains("  joints\n    Fixed1  fixed Base Shell.top ↔ Top Cap.bottom  ok"))
    }

    @Test("A joint that stops holding shows up among the status changes")
    func jointStatusChange() async throws {
        let harness = try await boxAndLid()
        _ = try await harness.call("add_joint", mate)

        let result = try await harness.call("delete_feature", ["feature": "Cap", "part": "Lid"])

        #expect(result.message.contains("Fixed1: ok → failed: b: Top did not build: part Lid has no bodies"))
    }
}
