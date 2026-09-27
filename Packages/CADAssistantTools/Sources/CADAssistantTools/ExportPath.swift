import CADModel
import Darwin
import Foundation

/// Where the `export` tool may write: a relative path inside the folder the host grants.
public enum ExportPath {
    /// The file inside `directory` that `path` names, with the format's extension, after checking that it resolves
    /// inside it. Creates nothing; `ExportDestination.write` creates the missing folders.
    public static func resolve(_ path: String, in directory: URL, format: ExportFormat, overwrite: Bool)
        throws(ExportError) -> ExportDestination
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
        guard !file.hasPrefix(".") else {
            throw ExportError(
                "'\(trimmed)' starts with a dot; give a visible file name, e.g. \"part.\(format.fileExtension)\"."
            )
        }
        let fileExtension = (file as NSString).pathExtension.lowercased()
        if let other = ExportFormat.allCases.first(where: { $0.fileExtension == fileExtension }), other != format {
            throw ExportError(
                "'\(trimmed)' names a \(other.displayName) file, but the format is \(format.displayName)."
            )
        }
        if fileExtension != format.fileExtension {
            file += ".\(format.fileExtension)"
        }

        let (base, rootMissing) = existingAncestor(of: directory.standardizedFileURL)
        let root = rootMissing.reduce(base) { $0.appending(path: $1) }
        var existing = root
        var missing = components
        if rootMissing.isEmpty {
            missing = []
            for (index, component) in components.enumerated() {
                let next = existing.appending(path: component)
                switch entry(at: next) {
                case .missing:
                    missing = Array(components[index...])
                case .directory:
                    existing = next
                    continue
                case .file:
                    throw ExportError("'\(trimmed)' goes through \(component), which is a file, not a folder.")
                case .symbolicLink:
                    let target = next.resolvingSymlinksInPath().standardizedFileURL
                    guard case .directory = entry(at: target) else {
                        var info = stat()
                        if stat(next.path, &info) != 0 {
                            throw ExportError("'\(trimmed)' goes through \(component), a symbolic link to nothing.")
                        }
                        throw ExportError("'\(trimmed)' goes through \(component), which is a file, not a folder.")
                    }
                    guard isInside(target, root) else {
                        throw ExportError("'\(trimmed)' leads outside the export folder through \(component).")
                    }
                    existing = target
                    continue
                }
                break
            }
        }
        let folder = missing.reduce(existing) { $0.appending(path: $1) }
        let url = folder.appending(path: file)
        let display = relative(url, to: root)
        if missing.isEmpty {
            switch entry(at: url) {
            case .symbolicLink:
                throw ExportError("'\(trimmed)' is a symbolic link; export to another name.")
            case .missing:
                break
            case .file, .directory:
                guard overwrite else {
                    throw ExportError("\(display) already exists; pass overwrite: true to replace it.")
                }
            }
        }
        let inRoot = relative(existing, to: root).split(separator: "/").map(String.init)
        return ExportDestination(
            url: url, display: display, base: base,
            folders: rootMissing + (existing.path == root.path ? [] : inRoot) + missing, file: file,
            overwrite: overwrite
        )
    }

    static func relative(_ url: URL, to root: URL) -> String {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    private static func isInside(_ url: URL, _ root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path + "/")
    }

    enum Entry {
        case missing, directory, file, symbolicLink
    }

    /// What is at `url`, without following a symbolic link there.
    static func entry(at url: URL) -> Entry {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return .missing }
        switch info.st_mode & S_IFMT {
        case S_IFLNK: return .symbolicLink
        case S_IFDIR: return .directory
        default: return .file
        }
    }

    /// The deepest folder of `directory` that exists, with its symbolic links resolved, and the names below it that
    /// do not exist yet.
    private static func existingAncestor(of directory: URL) -> (URL, [String]) {
        var missing: [String] = []
        var current = directory
        while case .missing = entry(at: current), current.path != "/" {
            missing.insert(current.lastPathComponent, at: 0)
            current = current.deletingLastPathComponent().standardizedFileURL
        }
        return (current.resolvingSymlinksInPath().standardizedFileURL, missing)
    }
}

/// A checked export target. `write` creates the missing folders without following symbolic links, lets the export
/// write a private temporary file, and moves that into place: without replacing anything unless `overwrite`, and
/// never through a symbolic link.
public struct ExportDestination: Sendable {
    /// The file the export ends up in.
    public let url: URL
    /// `url` relative to the export folder.
    public let display: String
    let base: URL
    /// The folders from `base` to the file's folder, none of them a symbolic link.
    let folders: [String]
    let file: String
    let overwrite: Bool

    nonisolated(nonsending) public func write<Value>(_ export: (URL) async throws(ExportError) -> Value)
        async throws(ExportError) -> Value
    {
        var directory = Darwin.open(base.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw failure("open the export folder") }
        var opened = [directory]
        var created: [(parent: Int32, name: String)] = []
        defer { opened.forEach { _ = Darwin.close($0) } }
        func removeCreated() {
            for (parent, name) in created.reversed() {
                _ = unlinkat(parent, name, AT_REMOVEDIR)
            }
        }
        var folderURL = base
        for name in folders {
            var next = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT, mkdirat(directory, name, 0o755) == 0 {
                created.append((directory, name))
                next = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard next >= 0 else {
                removeCreated()
                throw ExportError("\(display) changed while exporting: \(name) is no longer a folder.")
            }
            opened.append(next)
            directory = next
            folderURL.append(path: name)
        }
        let temporary = ".\(file).\(UUID().uuidString).export"
        guard mkdirat(directory, temporary, 0o700) == 0 else {
            let error = failure("create a temporary folder for \(display)")
            removeCreated()
            throw error
        }
        let temporaryURL = folderURL.appending(path: temporary)
        let temporaryDirectory = openat(directory, temporary, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if temporaryDirectory >= 0 {
            opened.append(temporaryDirectory)
        }
        func removeTemporary() {
            if temporaryDirectory >= 0 {
                _ = unlinkat(temporaryDirectory, file, 0)
            }
            if unlinkat(directory, temporary, AT_REMOVEDIR) != 0 {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }
        do throws(ExportError) {
            guard temporaryDirectory >= 0 else { throw failure("open the temporary folder for \(display)") }
            let value = try await export(temporaryURL.appending(path: file))
            let flags = overwrite ? 0 : UInt32(RENAME_EXCL)
            guard renameatx_np(temporaryDirectory, file, directory, file, flags) == 0 else {
                if errno == EEXIST {
                    throw ExportError("\(display) already exists; pass overwrite: true to replace it.")
                }
                throw failure("move the export to \(display)")
            }
            removeTemporary()
            return value
        } catch {
            removeTemporary()
            removeCreated()
            throw error
        }
    }

    private func failure(_ action: String) -> ExportError {
        ExportError("Could not \(action): \(String(cString: strerror(errno))).")
    }
}
