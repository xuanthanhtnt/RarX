import Foundation

/// Phân tích đầu ra `7zz l -slt` (danh sách kỹ thuật).
enum ListParser {
    struct Raw {
        var archiveBlocks: [[(key: String, value: String)]] = []
        var entryBlocks: [[String: String]] = []
    }

    static func parseRaw(_ text: String) -> Raw {
        enum Section { case header, archive, entries }
        var section = Section.header
        var raw = Raw()
        var currentArchive: [(key: String, value: String)] = []
        var currentEntry: [String: String] = [:]
        var lastKey: String?

        func flushArchive() {
            if !currentArchive.isEmpty { raw.archiveBlocks.append(currentArchive) }
            currentArchive = []
        }
        func flushEntry() {
            if !currentEntry.isEmpty { raw.entryBlocks.append(currentEntry) }
            currentEntry = [:]
        }

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        for rawLine in lines {
            var line = String(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }

            if line == "--" && section != .entries {
                flushArchive()
                section = .archive
                lastKey = nil
                continue
            }
            if line.hasPrefix("----------") && line.allSatisfy({ $0 == "-" }) {
                flushArchive()
                section = .entries
                lastKey = nil
                continue
            }
            if section == .header { continue }

            if line.isEmpty {
                if section == .archive { flushArchive() } else { flushEntry() }
                lastKey = nil
                continue
            }

            let key: String
            let value: String
            if let separator = line.range(of: " = ") {
                key = String(line[..<separator.lowerBound])
                value = String(line[separator.upperBound...])
            } else if line.hasSuffix(" =") {
                key = String(line.dropLast(2))
                value = ""
            } else if let lastKey {
                // Dòng tiếp theo của một giá trị nhiều dòng (ví dụ ghi chú).
                if section == .archive, let index = currentArchive.lastIndex(where: { $0.key == lastKey }) {
                    currentArchive[index].value += "\n" + line
                } else if section == .entries {
                    currentEntry[lastKey, default: ""] += "\n" + line
                }
                continue
            } else {
                continue
            }

            if section == .archive {
                currentArchive.append((key: key, value: value))
            } else {
                if key == "Path", currentEntry["Path"] != nil { flushEntry() }
                currentEntry[key] = value
            }
            lastKey = key
        }
        flushArchive()
        flushEntry()
        return raw
    }

    static func parse(_ text: String, archiveURL: URL) -> ArchiveListing {
        let raw = parseRaw(text)
        var info = ArchiveInfo()
        var merged: [String: String] = [:]
        for block in raw.archiveBlocks {
            for pair in block where merged[pair.key] == nil {
                merged[pair.key] = pair.value
            }
            info.rawProperties += block.filter { $0.key != "Path" }
        }
        // Với tệp chia phần, khối đầu là "Split", khối cuối mới là định dạng thật (7z, zip…).
        let types = raw.archiveBlocks.compactMap { block in block.first(where: { $0.key == "Type" })?.value }
        info.typeName = types.last ?? ""
        if types.contains("Split") { info.isMultiVolume = true }
        info.physicalSize = Int64(merged["Physical Size"] ?? "") ?? fileSize(archiveURL)
        info.method = nonEmpty(merged["Method"])
        if let solid = merged["Solid"] { info.solid = solid == "+" }
        info.blocks = Int(merged["Blocks"] ?? "")
        if merged["Multivolume"] == "+" { info.isMultiVolume = true }
        info.volumeCount = Int(merged["Volumes"] ?? "")
        info.comment = nonEmpty(merged["Comment"])
        info.characteristics = nonEmpty(merged["Characteristics"])
        if merged["Encrypted"] == "+" { info.headersEncrypted = true }
        if let warning = nonEmpty(merged["Warnings"]) { info.warnings.append(warning) }
        if let error = nonEmpty(merged["Errors"]) { info.warnings.append(error) }

        let entries = raw.entryBlocks.compactMap(entry(from:))
        return ArchiveListing(info: info, entries: entries)
    }

    private static func entry(from block: [String: String]) -> ArchiveEntry? {
        guard let path = block["Path"], !path.isEmpty else { return nil }
        let attributes = nonEmpty(block["Attributes"])
        let mode = nonEmpty(block["Mode"])
        var unixMode: String?
        var winFlags = ""
        if let attributes {
            let parts = attributes.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                winFlags = String(parts[0])
                unixMode = String(parts[1])
            } else if attributes.first == "-" || attributes.first == "d" || attributes.first == "l" {
                unixMode = attributes
            } else {
                winFlags = attributes
            }
        }
        if unixMode == nil { unixMode = mode }

        let isDirectory = block["Folder"] == "+"
            || winFlags.contains("D")
            || unixMode?.first == "d"
        let isSymlink = unixMode?.first == "l" || nonEmpty(block["Symbolic Link"]) != nil

        return ArchiveEntry(
            path: path.replacingOccurrences(of: "\\", with: "/"),
            isDirectory: isDirectory,
            size: Int64(block["Size"] ?? "") ?? 0,
            packedSize: Int64(block["Packed Size"] ?? ""),
            modified: parseDate(block["Modified"]),
            crc: nonEmpty(block["CRC"]),
            encrypted: block["Encrypted"] == "+",
            method: nonEmpty(block["Method"]),
            attributes: attributes ?? mode,
            isSymlink: isSymlink,
            comment: nonEmpty(block["Comment"])
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let dateLock = NSLock()

    static func parseDate(_ value: String?) -> Date? {
        guard let value, value.count >= 19 else { return nil }
        let head = String(value.prefix(19))
        dateLock.lock()
        defer { dateLock.unlock() }
        return dateFormatter.date(from: head)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
