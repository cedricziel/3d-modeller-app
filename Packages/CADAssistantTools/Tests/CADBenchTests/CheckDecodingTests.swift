import Testing

@testable import CADBench

@Suite("Check decoding")
struct CheckDecodingTests {
    @Test("Every check type decodes with its defaults")
    func decodesEveryType() throws {
        #expect(try Bench.check(#"{"type": "gate"}"#) == .gate)
        #expect(try Bench.check(#"{"type": "bodyCount", "equals": 2}"#) == .bodyCount(2))
        #expect(
            try Bench.check(#"{"type": "boundingBox", "body": "Body1", "max": [1, 2, 3]}"#)
                == .boundingBox(
                    BodySelector(body: "Body1"), min: nil, max: SIMD3(1, 2, 3), size: nil, tolerance: 0.01))
        #expect(
            try Bench.check(#"{"type": "volume", "part": "P", "expected": 100}"#)
                == .volume(BodySelector(part: "P"), expected: 100, tolerance: 0.005))
        #expect(
            try Bench.check(#"{"type": "parameter", "name": "t", "value": 10}"#)
                == .parameter(name: "t", value: 10, tolerance: 1e-6))
        #expect(
            try Bench.check(#"{"type": "featureCount", "feature": "cylinder", "equals": 2}"#)
                == .featureCount(.cylinder, min: 2, max: 2))
        #expect(
            try Bench.check(#"{"type": "featureCount", "feature": "box", "min": 1}"#)
                == .featureCount(.box, min: 1, max: nil))
        #expect(try Bench.check(#"{"type": "referenceIoU", "threshold": 0.99}"#) == .referenceIoU(threshold: 0.99))
        #expect(
            try Bench.check(#"{"type": "unchangedExcept", "features": ["Hole"]}"#)
                == .unchangedExcept(
                    features: ["Hole"], parameters: [], instances: [], joints: [], allowNewFeatures: false))
        #expect(try Bench.check(#"{"type": "instanceCount", "equals": 3}"#) == .instanceCount(3))
        #expect(
            try Bench.check(#"{"type": "instanceBounds", "instance": "Top", "min": [0, 0, 15]}"#)
                == .instanceBounds(instance: "Top", min: SIMD3(0, 0, 15), max: nil, size: nil, tolerance: 0.01))
        #expect(try Bench.check(#"{"type": "noInterference"}"#) == .noInterference)
        #expect(
            try Bench.check(#"{"type": "unchangedExcept", "instances": ["Top"]}"#)
                == .unchangedExcept(
                    features: [], parameters: [], instances: ["Top"], joints: [], allowNewFeatures: false))
        #expect(
            try Bench.check(#"{"type": "unchangedExcept", "joints": ["Hinge"]}"#)
                == .unchangedExcept(
                    features: [], parameters: [], instances: [], joints: ["Hinge"], allowNewFeatures: false))
        #expect(try Bench.check(#"{"type": "jointsSatisfied"}"#) == .jointsSatisfied(minimum: 1, kinds: []))
        #expect(
            try Bench.check(#"{"type": "jointsSatisfied", "minimum": 2, "kinds": ["revolute"]}"#)
                == .jointsSatisfied(minimum: 2, kinds: [.revolute]))
        #expect(
            try Bench.check(
                #"{"type": "instancePosition", "instance": "Pin", "relativeTo": "Base", "translation": [20, 20, 0]}"#)
                == .instancePosition(
                    instance: "Pin", relativeTo: "Base", translation: SIMD3(20, 20, 0), tolerance: 0.01))
    }

    @Test(
        "Malformed checks are refused",
        arguments: [
            #"{"type": "gate", "strict": true}"#,
            #"{"type": "boundingBox", "min": [1, 2]}"#,
            #"{"type": "boundingBox", "tolerance": 1}"#,
            #"{"type": "featureCount", "feature": "cylinder"}"#,
            #"{"type": "featureCount", "feature": "loft", "min": 1}"#,
            #"{"type": "volume"}"#,
            #"{"type": "overlap"}"#,
            #"{"type": "instanceBounds", "instance": "Top"}"#,
            #"{"type": "noInterference", "instances": ["A"]}"#,
            #"{"type": "jointsSatisfied", "kinds": ["weld"]}"#,
            #"{"type": "jointsSatisfied", "count": 1}"#,
            #"{"type": "instancePosition", "instance": "Pin"}"#,
            #"{"type": "instancePosition", "translation": [1, 2, 3]}"#,
        ])
    func decodingRefusals(json: String) {
        #expect(throws: (any Error).self) { try Bench.check(json) }
    }

    @Test("Descriptions say what is checked")
    func descriptions() {
        #expect(Check.bodyCount(1).description == "body count = 1")
        #expect(
            Check.volume(BodySelector(), expected: 23528.7611, tolerance: 0.002).description
                == "volume of all bodies = 23528.761 mm³ ±0.2%")
        #expect(
            Check.boundingBox(
                BodySelector(body: "Body1"), min: SIMD3(0, 0, 0), max: SIMD3(80, 50, 6), size: nil, tolerance: 0.01
            ).description == "bounding box of Body1: min (0, 0, 0), max (80, 50, 6) ±0.01 mm")
        #expect(Check.featureCount(.cylinder, min: 2, max: nil).description == "cylinder features ≥ 2")
        #expect(
            Check.unchangedExcept(
                features: ["Hole"], parameters: ["t"], instances: [], joints: [], allowNewFeatures: true
            )
            .description
                == "unchanged except features Hole, parameters t, new features allowed")
        #expect(Check.instanceCount(3).description == "instance count = 3")
        #expect(
            Check.instanceBounds(instance: "Top", min: SIMD3(0, 0, 15), max: nil, size: nil, tolerance: 0.01)
                .description == "bounds of instance Top: min (0, 0, 15) ±0.01 mm")
        #expect(
            Check.instanceBounds(instance: nil, min: nil, max: SIMD3(1, 2, 3), size: nil, tolerance: 0.01)
                .description == "bounds of all instances: max (1, 2, 3) ±0.01 mm")
        #expect(Check.noInterference.description == "no interference between instances")
        #expect(
            Check.unchangedExcept(features: [], parameters: [], instances: ["Top"], joints: [], allowNewFeatures: false)
                .description == "unchanged except instances Top")
    }
}
