import CADModel
import Foundation

/// Where the `export` tool may write: a relative path inside the folder the host grants.
public enum ExportPath {
    /// The file inside `directory` that `path` names, with the format's extension. Creates the directory and any
    /// missing subfolders, after checking that they resolve inside it.
    public static func resolve(_ path: String, in directory: URL, format: ExportFormat, overwrite: Bool)
        throws(ExportError) -> URL
    {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExportError("'path' is empty.") }
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else {
            throw ExportError(
                "'\(trimmed)' is not relative; give a path inside the export folder, e.g. \"part.\(format.fileExtension)\"."
            )
        }
        var components = trimmed.split(separator: "/").map(String.init).filter { $0 != "." }
        guard !components.contains("..") else {
            throw ExportError("'\(trimmed)' leaves the export folder; '..' is not allowed.")
        }
        guard var file = components.popLast() else { throw ExportError("'\(trimmed)' names no file.") }
        let fileExtension = (file as NSString).pathExtension.lowercased()
        if let other = ExportFormat.allCases.first(where: { $0.fileExtension == fileExtension }), other != format {
            throw ExportError(
                "'\(trimmed)' names a \(other.displayName) file, but the format is \(format.displayName).")
        }
        if fileExtension != format.fileExtension { file += ".\(format.fileExtension)" }

        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ExportError("Could not create the export folder \(directory.path): \(error.localizedDescription)")
        }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        var existing = root
        var missing: [String] = []
        for (index, component) in components.enumerated() {
            let next = existing.appending(path: component)
            guard manager.fileExists(atPath: next.path) else {
                missing = Array(components[index...])
                break
            }
            existing = next.resolvingSymlinksInPath().standardizedFileURL
            guard isInside(existing, root) else {
                throw ExportError("'\(trimmed)' leads outside the export folder through \(component).")
            }
        }
        let folder = missing.reduce(existing) { $0.appending(path: $1) }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw ExportError("Could not create \(folder.path): \(error.localizedDescription)")
        }
        let url = folder.appending(path: file)
        if (try? manager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw ExportError("'\(trimmed)' is a symbolic link; export to another name.")
        }
        if manager.fileExists(atPath: url.path), !overwrite {
            throw ExportError("\(relative(url, to: root)) already exists; pass overwrite: true to replace it.")
        }
        return url
    }

    static func relative(_ url: URL, to root: URL) -> String {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    private static func isInside(_ url: URL, _ root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path + "/")
    }
}
