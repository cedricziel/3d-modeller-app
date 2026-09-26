import CADModel
import Foundation
import Synchronization
import Testing

@testable import CADAssistantTools

/// Holds every box build until released, so a test can overlap two rebuilds.
/// `pass()` blocks a cooperative thread, so tests wait for it with `waitUntilEntered()` rather than
/// polling with `Task.sleep`, whose wake-up needs a free thread from the same pool.
final class Gate: Sendable {
    private let state = Mutex((entered: 0, open: false, waiters: [CheckedContinuation<Void, Never>]()))

    var entered: Int { state.withLock { $0.entered } }

    func pass() {
        let waiters = state.withLock { state in
            state.entered += 1
            defer { state.waiters = [] }
            return state.waiters
        }
        waiters.forEach { $0.resume() }
        let deadline = Date().addingTimeInterval(10)
        while !state.withLock({ $0.open }) {
            if Date() > deadline {
                Issue.record("The gate was never opened")
                return
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            let entered = state.withLock { state in
                if state.entered > 0 { return true }
                state.waiters.append(continuation)
                return false
            }
            if entered { continuation.resume() }
        }
    }

    func open() { state.withLock { $0.open = true } }
}

final class Counter: Sendable {
    private let value = Mutex(0)
    var count: Int { value.withLock { $0 } }
    func increment() { value.withLock { $0 += 1 } }
}

@MainActor
@Suite("CAD session", .serialized)
struct CADSessionTests {
    private func sphereDocument(_ name: String) -> CADDocument {
        CADDocument(parts: [
            Part(name: "P", features: [Feature(name: name, kind: .primitive(PrimitiveFeature(.sphere(radius: 1))))])
        ])
    }

    @Test("A new session lists its document as not built until it rebuilds")
    func listingFollowsRebuild() async throws {
        let plate = Fixtures.plate()
        let session = CADSession(document: plate, kernel: FakeKernel())

        #expect(session.result == nil)
        #expect(session.currentListing().contains("Base  box width×depth×t at origin → Body1  not built"))

        let result = try await session.rebuild()

        #expect(session.result == result)
        #expect(session.listing == DocumentListing.render(plate, result: result))
        #expect(session.currentListing() == session.listing)
        #expect(session.assistantContext().contextDescription.hasSuffix(session.listing))
    }

    @Test("Applying an edit hands it to the commit hook with its action name, then rebuilds")
    func applyCommits() async throws {
        let session = CADSession(document: CADDocument(), kernel: FakeKernel())
        var commits: [(CADDocument, String)] = []
        session.onCommit = { commits.append(($0, $1)) }
        let edited = Fixtures.plate()

        let result = await session.apply(edited, actionName: "Add Base")

        #expect(commits.count == 1)
        #expect(commits.first?.0 == edited)
        #expect(commits.first?.1 == "Add Base")
        #expect(session.document == edited)
        #expect(result?.parts.first?.features.count == 6)
        #expect(session.result == result)
    }

    @Test("Loading the document the session already built does not rebuild it again")
    func loadSkipsCurrentDocument() async throws {
        let boxes = Counter()
        let plate = Fixtures.plate()
        let session = CADSession(document: plate, kernel: FakeKernel(onBox: { boxes.increment() }))

        await session.load(plate)
        let afterFirst = boxes.count
        await session.load(session.document)

        #expect(afterFirst == 1)
        #expect(boxes.count == 1)
        #expect(session.result != nil)
    }

    @Test("A slow rebuild of an older document never replaces the result of a newer one")
    func staleResultDropped() async throws {
        let gate = Gate()
        let session = CADSession(document: CADDocument(), kernel: FakeKernel(onBox: { gate.pass() }))
        let slow = Task { await session.load(Fixtures.plate()) }
        await gate.waitUntilEntered()

        let newer = sphereDocument("Ball")
        await session.load(newer)
        gate.open()
        await slow.value

        #expect(session.document == newer)
        #expect(session.result?.parts.first?.features.map(\.name) == ["Ball"])
        #expect(session.listing.contains("Ball  sphere r=1 at origin → Body1  ok"))
    }

    @Test("The current result is rebuilt on demand when the document changed since the last rebuild")
    func currentResultOnDemand() async throws {
        let session = CADSession(document: sphereDocument("Ball"), kernel: FakeKernel())

        let result = await session.currentResult()

        #expect(result?.parts.first?.features.first?.status == .ok)
        #expect(await session.currentResult() == result)
    }

    @Test("A load whose caller is cancelled still finishes the rebuild the next load waits for")
    func cancelledLoadStillBuilds() async throws {
        let gate = Gate()
        let plate = Fixtures.plate()
        let session = CADSession(document: CADDocument(), kernel: FakeKernel(onBox: { gate.pass() }))
        let first = Task { await session.load(plate) }
        await gate.waitUntilEntered()

        first.cancel()
        let second = Task { await session.load(plate) }
        gate.open()
        await first.value
        await second.value

        #expect(session.result?.parts.first?.features.count == 6)
        #expect(session.listing.contains("Base  box width×depth×t at origin → Body1  ok"))
    }

    @Test("Asking for the current result while its rebuild runs waits for that rebuild instead of starting another")
    func currentResultJoinsRunningBuild() async throws {
        let gate = Gate()
        let boxes = Counter()
        let plate = Fixtures.plate()
        let session = CADSession(
            document: CADDocument(),
            kernel: FakeKernel(onBox: {
                boxes.increment()
                gate.pass()
            }))
        let load = Task { await session.load(plate) }
        await gate.waitUntilEntered()

        let current = Task { await session.currentResult() }
        for _ in 0..<10 { await Task.yield() }
        gate.open()
        await load.value
        let result = await current.value

        #expect(boxes.count == 1)
        #expect(result == session.result)
    }

    @Test("Adopting a host document takes effect at once and the next load rebuilds it")
    func adoptIsImmediate() async throws {
        let session = CADSession(document: CADDocument(), kernel: FakeKernel())
        let ball = sphereDocument("Ball")

        session.adopt(ball)

        #expect(session.document == ball)
        #expect(session.currentListing().contains("Ball  sphere r=1 at origin → Body1  not built"))
        await session.load(ball)
        #expect(session.result?.parts.first?.features.map(\.name) == ["Ball"])
    }

    @Test("A write that waited for a rebuild reports against the document it edits, not the one it waited for")
    func writeReportsAgainstEditedDocument() async throws {
        let gate = Gate()
        let plate = Fixtures.plate()
        let session = CADSession(document: plate, kernel: FakeKernel(onBox: { gate.pass() }))
        let write = Task { await session.setParameter(["name": "depth", "expression": 41]) }
        await gate.waitUntilEntered()

        var fixed = plate
        fixed.parts[0].features[3].kind = .primitive(
            PrimitiveFeature(.cone(bottomRadius: 3, topRadius: 1, height: 5)))
        session.adopt(fixed)
        gate.open()
        let result = await write.value

        #expect(result.success)
        #expect(!result.message.contains("Status changes elsewhere"))
        #expect(
            result.message.hasSuffix(
                """
                Listing changes:
                  - parameters: width = 60, depth = 40, t = 10, hole_d = 5.5, hole_r = hole_d / 2 (= 2.75)
                  + parameters: width = 60, depth = 41, t = 10, hole_d = 5.5, hole_r = hole_d / 2 (= 2.75)
                """))
        #expect(session.document.parts[0].features[3] == fixed.parts[0].features[3])
    }
}
