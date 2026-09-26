import Foundation

enum Frontmatter {
    /// The `key: value` lines between an opening and a closing `---` line, and the text after them.
    static func parse(_ text: String) -> (fields: [String: String], body: String)? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            fields[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (fields, String(body.drop { $0 == "\n" }))
    }
}
