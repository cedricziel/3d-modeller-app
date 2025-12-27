import Foundation
import Testing
@testable import SwiftUIAssistantTools

@Suite("TimeTool Tests")
struct TimeToolTests {
    let timeTool = TimeTool()

    // MARK: - Now Operation

    @Test("Get current time")
    func testGetCurrentTime() async throws {
        let result = try await timeTool.execute(arguments: ["operation": "now"])
        #expect(result.success == true)
        #expect(result.data?["timestamp"] != nil)
        #expect(result.data?["iso8601"] != nil)
        #expect(result.data?["year"] != nil)
        #expect(result.data?["month"] != nil)
        #expect(result.data?["day"] != nil)
    }

    @Test("Get current time with timezone")
    func testGetCurrentTimeWithTimezone() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "now",
            "timezone": "UTC"
        ])
        #expect(result.success == true)
        #expect(result.data?["timezone"] as? String == "GMT")
    }

    @Test("Get current time with format")
    func testGetCurrentTimeWithFormat() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "now",
            "format": "short"
        ])
        #expect(result.success == true)
        #expect(result.data?["formatted"] != nil)
    }

    // MARK: - Parse Operation

    @Test("Parse ISO 8601 date")
    func testParseISO8601() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "parse",
            "date": "2024-06-15T14:30:00Z"
        ])
        #expect(result.success == true)
        #expect(result.data?["year"] as? Int == 2024)
        #expect(result.data?["month"] as? Int == 6)
        #expect(result.data?["day"] as? Int == 15)
    }

    @Test("Parse date with dashes")
    func testParseDateWithDashes() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "parse",
            "date": "2024-12-25"
        ])
        #expect(result.success == true)
        #expect(result.data?["year"] as? Int == 2024)
        #expect(result.data?["month"] as? Int == 12)
        #expect(result.data?["day"] as? Int == 25)
    }

    @Test("Parse timestamp")
    func testParseTimestamp() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "parse",
            "date": "1700000000"
        ])
        #expect(result.success == true)
        #expect(result.data?["timestamp"] as? Double == 1700000000)
    }

    @Test("Parse invalid date fails")
    func testParseInvalidDate() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "parse",
            "date": "not a date"
        ])
        #expect(result.success == false)
        #expect(result.message.contains("Could not parse"))
    }

    @Test("Parse missing date parameter")
    func testParseMissingDate() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "parse"
        ])
        #expect(result.success == false)
        #expect(result.message.contains("Missing"))
    }

    // MARK: - Format Operation

    @Test("Format date as short")
    func testFormatShort() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "format",
            "date": "2024-06-15T14:30:00Z",
            "format": "short"
        ])
        #expect(result.success == true)
        #expect(result.data?["format"] as? String == "short")
    }

    @Test("Format date as medium")
    func testFormatMedium() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "format",
            "date": "2024-06-15T14:30:00Z",
            "format": "medium"
        ])
        #expect(result.success == true)
    }

    @Test("Format date as ISO 8601")
    func testFormatISO8601() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "format",
            "date": "2024-06-15T14:30:00Z",
            "format": "iso8601"
        ])
        #expect(result.success == true)
        let formatted = result.data?["formatted"] as? String
        #expect(formatted?.contains("2024") == true)
    }

    @Test("Format with custom pattern")
    func testFormatCustom() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "format",
            "date": "2024-06-15T14:30:00Z",
            "format": "yyyy-MM-dd"
        ])
        #expect(result.success == true)
    }

    // MARK: - Difference Operation

    @Test("Calculate time difference")
    func testDifference() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "difference",
            "date": "2024-01-01T00:00:00Z",
            "date2": "2024-01-02T00:00:00Z"
        ])
        #expect(result.success == true)
        #expect(result.data?["days"] as? Int == 1)
        #expect(result.data?["totalDays"] as? Double == 1.0)
    }

    @Test("Calculate difference in hours")
    func testDifferenceHours() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "difference",
            "date": "2024-01-01T00:00:00Z",
            "date2": "2024-01-01T05:00:00Z"
        ])
        #expect(result.success == true)
        #expect(result.data?["hours"] as? Int == 5)
        #expect(result.data?["totalHours"] as? Double == 5.0)
    }

    @Test("Difference with negative result")
    func testDifferenceNegative() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "difference",
            "date": "2024-01-02T00:00:00Z",
            "date2": "2024-01-01T00:00:00Z"
        ])
        #expect(result.success == true)
        let totalDays = result.data?["totalDays"] as? Double ?? 0
        #expect(totalDays < 0)
    }

    @Test("Difference missing second date")
    func testDifferenceMissingDate2() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "difference",
            "date": "2024-01-01"
        ])
        #expect(result.success == false)
        #expect(result.message.contains("date2"))
    }

    // MARK: - Add Operation

    @Test("Add days to date")
    func testAddDays() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "add",
            "date": "2024-01-01T00:00:00Z",
            "unit": "days",
            "value": 5.0
        ])
        #expect(result.success == true)
        let iso8601 = result.data?["iso8601"] as? String ?? ""
        #expect(iso8601.contains("2024-01-06"))
    }

    @Test("Add hours to date")
    func testAddHours() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "add",
            "date": "2024-01-01T00:00:00Z",
            "unit": "hours",
            "value": 3.0
        ])
        #expect(result.success == true)
        let iso8601 = result.data?["iso8601"] as? String ?? ""
        #expect(iso8601.contains("03:00"))
    }

    @Test("Add months to date")
    func testAddMonths() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "add",
            "date": "2024-01-15T00:00:00Z",
            "unit": "months",
            "value": 2.0
        ])
        #expect(result.success == true)
        let iso8601 = result.data?["iso8601"] as? String ?? ""
        #expect(iso8601.contains("2024-03"))
    }

    @Test("Subtract days (negative value)")
    func testSubtractDays() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "add",
            "date": "2024-01-10T00:00:00Z",
            "unit": "days",
            "value": -5.0
        ])
        #expect(result.success == true)
        let iso8601 = result.data?["iso8601"] as? String ?? ""
        #expect(iso8601.contains("2024-01-05"))
    }

    @Test("Add with invalid unit")
    func testAddInvalidUnit() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "add",
            "date": "2024-01-01",
            "unit": "centuries",
            "value": 1.0
        ])
        #expect(result.success == false)
        #expect(result.message.contains("Unknown time unit"))
    }

    @Test("Add missing unit parameter")
    func testAddMissingUnit() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "add",
            "date": "2024-01-01",
            "value": 5.0
        ])
        #expect(result.success == false)
        #expect(result.message.contains("unit"))
    }

    // MARK: - Convert Timezone Operation

    @Test("Convert to UTC")
    func testConvertToUTC() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "convert",
            "date": "2024-06-15T14:30:00Z",
            "timezone": "UTC"
        ])
        #expect(result.success == true)
        #expect(result.data?["timezone"] as? String == "GMT")
        #expect(result.data?["utcOffset"] as? Int == 0)
    }

    @Test("Convert to named timezone")
    func testConvertToNamedTimezone() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "convert",
            "date": "2024-06-15T14:30:00Z",
            "timezone": "America/New_York"
        ])
        #expect(result.success == true)
        #expect(result.data?["timezone"] as? String == "America/New_York")
    }

    @Test("Convert missing timezone")
    func testConvertMissingTimezone() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "convert",
            "date": "2024-06-15T14:30:00Z"
        ])
        #expect(result.success == false)
        #expect(result.message.contains("timezone"))
    }

    // MARK: - Error Cases

    @Test("Missing operation parameter")
    func testMissingOperation() async throws {
        let result = try await timeTool.execute(arguments: [:])
        #expect(result.success == false)
        #expect(result.message.contains("operation"))
    }

    @Test("Unknown operation")
    func testUnknownOperation() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": "unknown"
        ])
        #expect(result.success == false)
        #expect(result.message.contains("Unknown operation"))
    }

    // MARK: - Tool Metadata

    @Test("Tool has correct name and id")
    func testToolMetadata() {
        #expect(timeTool.name == "time")
        #expect(timeTool.id == "time")
        #expect(!timeTool.description.isEmpty)
    }

    @Test("Tool has parameters defined")
    func testToolParameters() {
        let params = timeTool.parameters
        #expect(params.count >= 1)

        let operationParam = params.first { $0.name == "operation" }
        #expect(operationParam != nil)
        #expect(operationParam?.required == true)
        #expect(operationParam?.enumValues?.contains("now") == true)
        #expect(operationParam?.enumValues?.contains("parse") == true)
        #expect(operationParam?.enumValues?.contains("format") == true)
        #expect(operationParam?.enumValues?.contains("difference") == true)
        #expect(operationParam?.enumValues?.contains("add") == true)
        #expect(operationParam?.enumValues?.contains("convert") == true)
    }
}
