import Foundation
import Testing
@testable import SwiftUIAssistant

@Suite("JSONValue Tests")
struct JSONValueTests {
    @Test("Booleans from JSONSerialization stay booleans")
    func decodedBooleansStayBooleans() throws {
        let object = try JSONSerialization.jsonObject(with: Data(#"{"on": true, "count": 1}"#.utf8))
        let value = try #require(JSONValue(object))

        #expect(value["on"] == .bool(true))
        #expect(value["count"] == .integer(1))
    }
}
