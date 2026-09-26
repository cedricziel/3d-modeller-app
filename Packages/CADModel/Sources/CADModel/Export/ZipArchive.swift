import Foundation

/// A zip archive of stored (uncompressed) entries, which OPC packages such as 3MF accept.
public struct ZipArchive: Sendable {
    private var entries: [(path: String, data: Data)] = []

    public init() {}

    public mutating func add(_ path: String, _ data: Data) {
        entries.append((path, data))
    }

    public func data() -> Data {
        var archive = Data()
        var directory = Data()
        for (path, data) in entries {
            let name = Data(path.utf8)
            let crc = Self.crc32(data)
            let offset = UInt32(archive.count)
            archive.appendLittleEndian(UInt32(0x0403_4B50))
            appendCommon(to: &archive, name: name, crc: crc, size: UInt32(data.count))
            archive.append(name)
            archive.append(data)

            directory.appendLittleEndian(UInt32(0x0201_4B50))
            directory.appendLittleEndian(UInt16(20))
            appendCommon(to: &directory, name: name, crc: crc, size: UInt32(data.count))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt32(0))
            directory.appendLittleEndian(offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt32(directory.count))
        archive.appendLittleEndian(directoryOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    /// Version needed, UTF-8 flag, stored, 1980-01-01 00:00, CRC, sizes, name length, no extra field.
    private func appendCommon(to data: inout Data, name: Data, crc: UInt32, size: UInt32) {
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(0x0800))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0x0021))
        data.appendLittleEndian(crc)
        data.appendLittleEndian(size)
        data.appendLittleEndian(size)
        data.appendLittleEndian(UInt16(name.count))
        data.appendLittleEndian(UInt16(0))
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    public static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }

    /// The stored entries of an archive, by path; for reading back what `data()` wrote.
    public static func entries(of data: Data) throws(ExportError) -> [String: Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22,
            let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: {
                bytes.littleEndianUInt32(at: $0) == 0x0605_4B50
            })
        else { throw ExportError("The file is not a zip archive") }
        let count = Int(bytes.littleEndianUInt16(at: end + 10))
        var cursor = Int(bytes.littleEndianUInt32(at: end + 16))
        var entries: [String: Data] = [:]
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, bytes.littleEndianUInt32(at: cursor) == 0x0201_4B50 else {
                throw ExportError("The zip directory is damaged")
            }
            let method = bytes.littleEndianUInt16(at: cursor + 10)
            let size = Int(bytes.littleEndianUInt32(at: cursor + 20))
            let nameLength = Int(bytes.littleEndianUInt16(at: cursor + 28))
            let extraLength = Int(bytes.littleEndianUInt16(at: cursor + 30))
            let commentLength = Int(bytes.littleEndianUInt16(at: cursor + 32))
            let local = Int(bytes.littleEndianUInt32(at: cursor + 42))
            guard cursor + 46 + nameLength + extraLength + commentLength <= bytes.count else {
                throw ExportError("The zip directory is damaged")
            }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            guard method == 0 else { throw ExportError("\(name) is compressed; only stored entries are read") }
            guard local + 30 <= bytes.count else { throw ExportError("The zip entry \(name) is damaged") }
            let start =
                local + 30 + Int(bytes.littleEndianUInt16(at: local + 26))
                + Int(bytes.littleEndianUInt16(at: local + 28))
            guard start + size <= bytes.count else { throw ExportError("The zip entry \(name) is truncated") }
            entries[name] = Data(bytes[start..<(start + size)])
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }
}
