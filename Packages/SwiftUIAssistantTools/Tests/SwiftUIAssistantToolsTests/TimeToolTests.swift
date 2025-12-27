import Foundation
import Testing
@testable import SwiftUIAssistantTools
import SwiftUIAssistant

@Suite("TimeTool Tests")
struct TimeToolTests {
    let timeTool = TimeTool()

    // MARK: - Now Operation

    @Test("Get current time")
    func testGetCurrentTime() async throws {
        let result = try await timeTool.execute(arguments: ["operation": .string("now")])
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
            "operation": .string("now"),
            "timezone": .string("UTC")
        ])
        #expect(result.success == true)
        #expect(result.data?["timezone"]?.stringValue == "GMT")
    }

    @Test("Get current time with format")
    func testGetCurrentTimeWithFormat() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("now"),
            "format": .string("short")
        ])
        #expect(result.success == true)
        #expect(result.data?["formatted"] != nil)
    }

    // MARK: - Parse Operation

    @Test("Parse ISO 8601 date")
    func testParseISO8601() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("parse"),
            "date": .string("2024-06-15T14:30:00Z")
        ])
        #expect(result.success == true)
        #expect(result.data?["year"]?.intValue == 2024)
        #expect(result.data?["month"]?.intValue == 6)
        #expect(result.data?["day"]?.intValue == 15)
    }

    @Test("Parse date with dashes")
    func testParseDateWithDashes() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("parse"),
            "date": .string("2024-12-25")
        ])
        #expect(result.success == true)
        #expect(result.data?["year"]?.intValue == 2024)
        #expect(result.data?["month"]?.intValue == 12)
        #expect(result.data?["day"]?.intValue == 25)
    }

    @Test("Parse timestamp")
    func testParseTimestamp() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("parse"),
            "date": .string("1700000000")
        ])
        #expect(result.success == true)
        #expect(result.data?["timestamp"]?.doubleValue == 1700000000)
    }

    @Test("Parse invalid date fails")
    func testParseInvalidDate() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("parse"),
            "date": .string("not a date")
        ])
        #expect(result.success == false)
        #expect(result.message.contains("Could not parse"))
    }

    @Test("Parse missing date parameter")
    func testParseMissingDate() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("parse")
        ])
        #expect(result.success == false)
        #expect(result.message.contains("Missing"))
    }

    // MARK: - Format Operation

    @Test("Format date as short")
    func testFormatShort() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("format"),
            "date": .string("2024-06-15T14:30:00Z"),
            "format": .string("short")
        ])
        #expect(result.success == true)
        #expect(result.data?["format"]?.stringValue == "short")
    }

    @Test("Format date as medium")
    func testFormatMedium() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("format"),
            "date": .string("2024-06-15T14:30:00Z"),
            "format": .string("medium")
        ])
        #expect(result.success == true)
    }

    @Test("Format date as ISO 8601")
    func testFormatISO8601() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("format"),
            "date": .string("2024-06-15T14:30:00Z"),
            "format": .string("iso8601")
        ])
        #expect(result.success == true)
        let formatted = result.data?["formatted"]?.stringValue
        #expect(formatted?.contains("2024") == true)
    }

    @Test("Format with custom pattern")
    func testFormatCustom() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("format"),
            "date": .string("2024-06-15T14:30:00Z"),
            "format": .string("yyyy-MM-dd")
        ])
        #expect(result.success == true)
    }

    // MARK: - Difference Operation

    @Test("Calculate time difference")
    func testDifference() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("difference"),
            "date": .string("2024-01-01T00:00:00Z"),
            "date2": .string("2024-01-02T00:00:00Z")
        ])
        #expect(result.success == true)
        #expect(result.data?["days"]?.intValue == 1)
        #expect(result.data?["totalDays"]?.doubleValue == 1.0)
    }

    @Test("Calculate difference in hours")
    func testDifferenceHours() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("difference"),
            "date": .string("2024-01-01T00:00:00Z"),
            "date2": .string("2024-01-01T05:00:00Z")
        ])
        #expect(result.success == true)
        #expect(result.data?["hours"]?.intValue == 5)
        #expect(result.data?["totalHours"]?.doubleValue == 5.0)
    }

    @Test("Difference with negative result")
    func testDifferenceNegative() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("difference"),
            "date": .string("2024-01-02T00:00:00Z"),
            "date2": .string("2024-01-01T00:00:00Z")
        ])
        #expect(result.success == true)
        let totalDays = result.data?["totalDays"]?.doubleValue ?? 0
        #expect(totalDays < 0)
    }

    @Test("Difference missing second date")
    func testDifferenceMissingDate2() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("difference"),
            "date": .string("2024-01-01")
        ])
        #expect(result.success == false)
        #expect(result.message.contains("date2"))
    }

    // MARK: - Add Operation

    @Test("Add days to date")
    func testAddDays() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("add"),
            "date": .string("2024-01-01T00:00:00Z"),
            "unit": .string("days"),
            "value": .number(5.0)
        ])
        #expect(result.success == true)
        let iso8601 = result.data?["iso8601"]?.stringValue ?? ""
        #expect(iso8601.contains("2024-01-06"))
    }

    @Test("Add hours to date")
    func testAddHours() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("add"),
            "date": .string("2024-01-01T00:00:00Z"),
            "unit": .string("hours"),
            "value": .number(3.0)
        ])
        #expect(result.success == true)
        let iso8601 = result.data?["iso8601"]?.stringValue ?? ""
        #expect(iso8601.contains("03:00"))
    }

    @Test("Add months to date")
    func testAddMonths() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("add"),
            "date": .string("2024-01-15T00:00:00Z"),
            "unit": .string("months"),
            "value": .number(2.0)
        ])
        #expect(result.success == true)
        let iso8601 = result.data?["iso8601"]?.stringValue ?? ""
        #expect(iso8601.contains("2024-03"))
    }

    @Test("Subtract days (negative value)")
    func testSubtractDays() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("add"),
            "date": .string("2024-01-10T00:00:00Z"),
            "unit": .string("days"),
            "value": .number(-5.0)
        ])
        #expect(result.success == true)
        let iso8601 = result.data?["iso8601"]?.stringValue ?? ""
        #expect(iso8601.contains("2024-01-05"))
    }

    @Test("Add with invalid unit")
    func testAddInvalidUnit() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("add"),
            "date": .string("2024-01-01"),
            "unit": .string("centuries"),
            "value": .number(1.0)
        ])
        #expect(result.success == false)
        #expect(result.message.contains("Unknown time unit"))
    }

    @Test("Add missing unit parameter")
    func testAddMissingUnit() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("add"),
            "date": .string("2024-01-01"),
            "value": .number(5.0)
        ])
        #expect(result.success == false)
        #expect(result.message.contains("unit"))
    }

    // MARK: - Convert Timezone Operation

    @Test("Convert to UTC")
    func testConvertToUTC() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("convert"),
            "date": .string("2024-06-15T14:30:00Z"),
            "timezone": .string("UTC")
        ])
        #expect(result.success == true)
        #expect(result.data?["timezone"]?.stringValue == "GMT")
        #expect(result.data?["utcOffset"]?.intValue == 0)
    }

    @Test("Convert to named timezone")
    func testConvertToNamedTimezone() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("convert"),
            "date": .string("2024-06-15T14:30:00Z"),
            "timezone": .string("America/New_York")
        ])
        #expect(result.success == true)
        #expect(result.data?["timezone"]?.stringValue == "America/New_York")
    }

    @Test("Convert missing timezone")
    func testConvertMissingTimezone() async throws {
        let result = try await timeTool.execute(arguments: [
            "operation": .string("convert"),
            "date": .string("2024-06-15T14:30:00Z")
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
            "operation": .string("unknown")
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
