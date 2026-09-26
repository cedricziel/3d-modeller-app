import Foundation
import Testing
@testable import CADModel

@Suite("Scalar")
struct ScalarTests {
    private func decode(_ json: String) throws -> Scalar {
        try JSONDecoder().decode(Scalar.self, from: Data(json.utf8))
    }

    @Test("A JSON number decodes as a number and re-encodes as one")
    func number() throws {
        let scalar = try decode("12.5")
        #expect(scalar == .number(12.5))
        #expect(String(decoding: try JSONEncoder().encode(scalar), as: UTF8.self) == "12.5")
    }

    @Test("A JSON string decodes as an expression and re-encodes as a string")
    func expression() throws {
        let scalar = try decode(#""width / 2""#)
        #expect(scalar == .expression("width / 2"))
        #expect(String(decoding: try JSONEncoder().encode(scalar), as: UTF8.self) == #""width \/ 2""#)
    }

    @Test("Anything else is a type mismatch")
    func rejectsOtherTypes() {
        #expect(throws: DecodingError.self) { try decode("true") }
        #expect(throws: DecodingError.self) { try decode("[1]") }
    }

    @Test("Descriptions print whole numbers without a fraction")
    func descriptions() {
        #expect(Scalar.number(10).description == "10")
        #expect(Scalar.number(2.5).description == "2.5")
        #expect(Scalar.expression("a+b").description == "a+b")
    }

    @Test("Literals build scalars")
    func literals() {
        let a: Scalar = 3
        let b: Scalar = 1.5
        let c: Scalar = "t * 2"
        #expect(a == .number(3))
        #expect(b == .number(1.5))
        #expect(c == .expression("t * 2"))
    }
}
