import Foundation
import SwiftUIAssistant

/// Tool for working with dates, times, and timezones
public struct TimeTool: AssistantTool, Sendable {
    public let id = "time"
    public let name = "time"
    public let description = "Gets current time, parses dates, calculates time differences, and converts between timezones."

    public var parameters: [ToolParameter] {
        [
            .enumParameter(
                "operation",
                description: "The time operation to perform",
                values: ["now", "parse", "format", "difference", "add", "convert"],
                required: true
            ),
            .optionalString("date", description: "Date string to parse or format (ISO 8601 or common formats)"),
            .optionalString("date2", description: "Second date for difference calculation"),
            .optionalString("format", description: "Output format (iso8601, short, medium, long, full, or custom pattern)"),
            .optionalString("timezone", description: "Target timezone (e.g., 'America/New_York', 'UTC', 'PST')"),
            .optionalString("unit", description: "Time unit for add operation (seconds, minutes, hours, days, weeks, months, years)"),
            .optionalNumber("value", description: "Value to add (can be negative to subtract)")
        ]
    }

    public init() {}

    public func execute(arguments: [String: Any]) async throws -> ToolExecutionResult {
        guard let operation = arguments["operation"] as? String else {
            return .failure("Missing required parameter: operation")
        }

        switch operation {
        case "now":
            return getCurrentTime(arguments: arguments)
        case "parse":
            return parseDate(arguments: arguments)
        case "format":
            return formatDate(arguments: arguments)
        case "difference":
            return calculateDifference(arguments: arguments)
        case "add":
            return addTime(arguments: arguments)
        case "convert":
            return convertTimezone(arguments: arguments)
        default:
            return .failure("Unknown operation: \(operation)")
        }
    }

    // MARK: - Operations

    private func getCurrentTime(arguments: [String: Any]) -> ToolExecutionResult {
        let now = Date()
        let timezone = getTimezone(from: arguments["timezone"] as? String)
        let format = arguments["format"] as? String ?? "iso8601"

        let formatted = formatDate(now, format: format, timezone: timezone)
        let iso8601 = ISO8601DateFormatter().string(from: now)

        return .success(
            "Current time: \(formatted)",
            data: [
                "timestamp": now.timeIntervalSince1970,
                "iso8601": iso8601,
                "formatted": formatted,
                "timezone": timezone.identifier,
                "year": Calendar.current.component(.year, from: now),
                "month": Calendar.current.component(.month, from: now),
                "day": Calendar.current.component(.day, from: now),
                "hour": Calendar.current.component(.hour, from: now),
                "minute": Calendar.current.component(.minute, from: now),
                "second": Calendar.current.component(.second, from: now),
                "weekday": Calendar.current.component(.weekday, from: now),
                "dayOfYear": Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 0
            ]
        )
    }

    private func parseDate(arguments: [String: Any]) -> ToolExecutionResult {
        guard let dateString = arguments["date"] as? String else {
            return .failure("Missing required parameter: date")
        }

        guard let date = parseDate(from: dateString) else {
            return .failure("Could not parse date: \(dateString)")
        }

        let iso8601 = ISO8601DateFormatter().string(from: date)

        return .success(
            "Parsed date: \(iso8601)",
            data: [
                "timestamp": date.timeIntervalSince1970,
                "iso8601": iso8601,
                "year": Calendar.current.component(.year, from: date),
                "month": Calendar.current.component(.month, from: date),
                "day": Calendar.current.component(.day, from: date),
                "hour": Calendar.current.component(.hour, from: date),
                "minute": Calendar.current.component(.minute, from: date),
                "second": Calendar.current.component(.second, from: date)
            ]
        )
    }

    private func formatDate(arguments: [String: Any]) -> ToolExecutionResult {
        guard let dateString = arguments["date"] as? String else {
            return .failure("Missing required parameter: date")
        }

        guard let date = parseDate(from: dateString) else {
            return .failure("Could not parse date: \(dateString)")
        }

        let format = arguments["format"] as? String ?? "medium"
        let timezone = getTimezone(from: arguments["timezone"] as? String)
        let formatted = formatDate(date, format: format, timezone: timezone)

        return .success(
            "Formatted: \(formatted)",
            data: [
                "formatted": formatted,
                "format": format,
                "timezone": timezone.identifier
            ]
        )
    }

    private func calculateDifference(arguments: [String: Any]) -> ToolExecutionResult {
        guard let dateString1 = arguments["date"] as? String else {
            return .failure("Missing required parameter: date")
        }
        guard let dateString2 = arguments["date2"] as? String else {
            return .failure("Missing required parameter: date2")
        }

        guard let date1 = parseDate(from: dateString1) else {
            return .failure("Could not parse first date: \(dateString1)")
        }
        guard let date2 = parseDate(from: dateString2) else {
            return .failure("Could not parse second date: \(dateString2)")
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date1,
            to: date2
        )

        let totalSeconds = date2.timeIntervalSince(date1)
        let totalMinutes = totalSeconds / 60
        let totalHours = totalMinutes / 60
        let totalDays = totalHours / 24

        let description = formatDifference(components)

        return .success(
            "Difference: \(description)",
            data: [
                "years": components.year ?? 0,
                "months": components.month ?? 0,
                "days": components.day ?? 0,
                "hours": components.hour ?? 0,
                "minutes": components.minute ?? 0,
                "seconds": components.second ?? 0,
                "totalSeconds": totalSeconds,
                "totalMinutes": totalMinutes,
                "totalHours": totalHours,
                "totalDays": totalDays,
                "description": description
            ]
        )
    }

    private func addTime(arguments: [String: Any]) -> ToolExecutionResult {
        guard let dateString = arguments["date"] as? String else {
            return .failure("Missing required parameter: date")
        }
        guard let unit = arguments["unit"] as? String else {
            return .failure("Missing required parameter: unit")
        }
        guard let value = arguments["value"] as? Double else {
            return .failure("Missing required parameter: value")
        }

        guard let date = parseDate(from: dateString) else {
            return .failure("Could not parse date: \(dateString)")
        }

        let intValue = Int(value)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        let component: Calendar.Component
        switch unit.lowercased() {
        case "seconds", "second": component = .second
        case "minutes", "minute": component = .minute
        case "hours", "hour": component = .hour
        case "days", "day": component = .day
        case "weeks", "week": component = .weekOfYear
        case "months", "month": component = .month
        case "years", "year": component = .year
        default:
            return .failure("Unknown time unit: \(unit)")
        }

        guard let resultDate = calendar.date(byAdding: component, value: intValue, to: date) else {
            return .failure("Could not calculate new date")
        }

        let iso8601 = ISO8601DateFormatter().string(from: resultDate)

        return .success(
            "Result: \(iso8601)",
            data: [
                "timestamp": resultDate.timeIntervalSince1970,
                "iso8601": iso8601,
                "originalDate": ISO8601DateFormatter().string(from: date),
                "added": intValue,
                "unit": unit
            ]
        )
    }

    private func convertTimezone(arguments: [String: Any]) -> ToolExecutionResult {
        guard let dateString = arguments["date"] as? String else {
            return .failure("Missing required parameter: date")
        }
        guard let timezoneString = arguments["timezone"] as? String else {
            return .failure("Missing required parameter: timezone")
        }

        guard let date = parseDate(from: dateString) else {
            return .failure("Could not parse date: \(dateString)")
        }

        let timezone = getTimezone(from: timezoneString)
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        formatter.timeZone = timezone

        let formatted = formatter.string(from: date)

        // Also get ISO 8601 in target timezone
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = timezone
        let iso8601 = isoFormatter.string(from: date)

        return .success(
            "Converted: \(formatted)",
            data: [
                "formatted": formatted,
                "iso8601": iso8601,
                "timezone": timezone.identifier,
                "abbreviation": timezone.abbreviation() ?? "",
                "utcOffset": timezone.secondsFromGMT() / 3600
            ]
        )
    }

    // MARK: - Helpers

    private func parseDate(from string: String) -> Date? {
        // Try ISO 8601 first
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        // Try common formats
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy",
            "MMMM d, yyyy",
            "MMM d, yyyy",
            "d MMM yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }

        // Try timestamp
        if let timestamp = Double(string) {
            return Date(timeIntervalSince1970: timestamp)
        }

        return nil
    }

    private func formatDate(_ date: Date, format: String, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timezone

        switch format.lowercased() {
        case "iso8601":
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.timeZone = timezone
            return isoFormatter.string(from: date)
        case "short":
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        case "medium":
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
        case "long":
            formatter.dateStyle = .long
            formatter.timeStyle = .long
        case "full":
            formatter.dateStyle = .full
            formatter.timeStyle = .full
        case "date":
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        case "time":
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
        default:
            // Custom format
            formatter.dateFormat = format
        }

        return formatter.string(from: date)
    }

    private func getTimezone(from string: String?) -> TimeZone {
        guard let string = string else {
            return TimeZone.current
        }

        // Try identifier
        if let tz = TimeZone(identifier: string) {
            return tz
        }

        // Try abbreviation
        if let tz = TimeZone(abbreviation: string) {
            return tz
        }

        // Try seconds from GMT
        if let offset = Int(string) {
            if let tz = TimeZone(secondsFromGMT: offset * 3600) {
                return tz
            }
        }

        return TimeZone.current
    }

    private func formatDifference(_ components: DateComponents) -> String {
        var parts: [String] = []

        if let years = components.year, years != 0 {
            parts.append("\(abs(years)) year\(abs(years) == 1 ? "" : "s")")
        }
        if let months = components.month, months != 0 {
            parts.append("\(abs(months)) month\(abs(months) == 1 ? "" : "s")")
        }
        if let days = components.day, days != 0 {
            parts.append("\(abs(days)) day\(abs(days) == 1 ? "" : "s")")
        }
        if let hours = components.hour, hours != 0 {
            parts.append("\(abs(hours)) hour\(abs(hours) == 1 ? "" : "s")")
        }
        if let minutes = components.minute, minutes != 0 {
            parts.append("\(abs(minutes)) minute\(abs(minutes) == 1 ? "" : "s")")
        }
        if let seconds = components.second, seconds != 0 {
            parts.append("\(abs(seconds)) second\(abs(seconds) == 1 ? "" : "s")")
        }

        if parts.isEmpty {
            return "0 seconds"
        }

        return parts.joined(separator: ", ")
    }
}
