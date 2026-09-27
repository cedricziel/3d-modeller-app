import Foundation

enum Frontmatter {
    /// The `key: value` lines between an opening and a closing `---` line, and the text after them.
    static func parse(_ text: String) -> (fields: [String: String], body: String)? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false
        )
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !blockScalarMarkers.contains(value) else { continue }
            fields[key] = unquoted(value)
        }
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (fields, String(body.drop { $0 == "\n" }))
    }

    private static let blockScalarMarkers: Set<String> = [">", "|", ">-", "|-"]

    /// Strips one matching pair of surrounding double or single quotes, if present.
    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last, first == last,
            first == "\"" || first == "'"
        else { return value }
        return String(value.dropFirst().dropLast())
    }
}
