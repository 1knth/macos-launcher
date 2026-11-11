import Foundation

public struct TokenDay: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public var claude: Int = 0
    public var codex: Int = 0
    public var pi: Int = 0
    public var total: Int { claude + codex + pi }
}

/// Parsed usage per log file, reused while a file's size and modification date are unchanged.
public struct TokenCache: Sendable {
    fileprivate var files: [URL: Entry] = [:]
    public init() {}

    fileprivate struct Entry: Sendable {
        let modified: Date
        let size: Int
        let records: [TokenRecord]
    }
}

fileprivate enum TokenSource: Sendable { case claude, codex, pi }

fileprivate struct TokenRecord: Sendable {
    let source: TokenSource
    /// Records sharing a key are one response; only the fullest is counted.
    let key: String?
    let date: Date
    let tokens: Int
}

public enum TokenHistory {
    public static func load(claudeDirectory: URL, codexDirectory: URL, piDirectory: URL? = nil, since: Date) -> [TokenDay] {
        var cache = TokenCache()
        return load(claudeDirectory: claudeDirectory, codexDirectory: codexDirectory, piDirectory: piDirectory, since: since, cache: &cache)
    }

    /// Reads usage metadata only. Prompt and response contents are never retained.
    /// Files last modified before `since` are skipped, and files unchanged since the cached read aren't read again.
    public static func load(claudeDirectory: URL, codexDirectory: URL, piDirectory: URL? = nil, since: Date, cache: inout TokenCache) -> [TokenDay] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        var sources = [(claudeDirectory, TokenSource.claude), (codexDirectory, .codex)]
        if let piDirectory { sources.append((piDirectory, .pi)) }
        var files: [URL: TokenCache.Entry] = [:]
        for (directory, source) in sources {
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: keys),
                      let modified = values.contentModificationDate, modified >= since else { continue }
                let size = values.fileSize ?? 0
                if let entry = cache.files[file], entry.modified == modified, entry.size == size {
                    files[file] = entry
                } else {
                    autoreleasepool {
                        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return }
                        files[file] = .init(modified: modified, size: size, records: records(in: data, source: source))
                    }
                }
            }
        }
        cache.files = files

        var days: [Date: TokenDay] = [:]
        let calendar = Calendar.current
        func add(_ record: TokenRecord) {
            guard record.date >= since, record.tokens > 0 else { return }
            let day = calendar.startOfDay(for: record.date)
            var value = days[day] ?? TokenDay(date: day)
            switch record.source {
            case .claude: value.claude += record.tokens
            case .codex: value.codex += record.tokens
            case .pi: value.pi += record.tokens
            }
            days[day] = value
        }
        var fullest: [String: TokenRecord] = [:]
        for entry in files.values {
            for record in entry.records {
                if let key = record.key {
                    if record.tokens > (fullest[key]?.tokens ?? -1) { fullest[key] = record }
                } else { add(record) }
            }
        }
        fullest.values.forEach(add)
        return days.values.sorted { $0.date < $1.date }
    }

    private static func records(in data: Data, source: TokenSource) -> [TokenRecord] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        func date(_ value: Any?) -> Date? {
            guard let text = value as? String else { return nil }
            return formatter.date(from: text) ?? fallback.date(from: text)
        }
        func count(_ object: [String: Any], _ key: String) -> Int {
            guard let n = object[key] as? NSNumber, n.doubleValue.isFinite,
                  n.doubleValue >= 0, n.doubleValue < Double(Int.max) else { return 0 }
            return n.intValue
        }
        // Most lines are message content; only parse the ones that can carry usage.
        // Pi tool results embed whole subagent transcripts, so match its top-level assistant records,
        // which Pi writes near the start of the line.
        let needle = Array((source == .claude ? "\"usage\"" : source == .codex ? "\"token_count\"" : "\"message\":{\"role\":\"assistant\"").utf8)
        var result: [TokenRecord] = []
        var previous = 0
        for line in lines(in: data, containing: needle, prefix: source == .pi ? 512 : nil) {
            guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            switch source {
            case .claude:
                guard let message = record["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let id = message["id"] as? String,
                      let timestamp = date(record["timestamp"]) else { continue }
                let total = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].reduce(0) { $0 + count(usage, $1) }
                // Streaming records repeat a message, and resumed sessions copy it into other files.
                result.append(TokenRecord(source: .claude, key: "claude:" + id, date: timestamp, tokens: total))
            case .codex:
                guard let payload = record["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let usage = info["total_token_usage"] as? [String: Any] else { continue }
                // Snapshots are cumulative per session; count only the growth.
                let total = count(usage, "total_tokens")
                let delta = max(0, total - previous)
                previous = max(previous, total)
                if let timestamp = date(record["timestamp"]) { result.append(TokenRecord(source: .codex, key: nil, date: timestamp, tokens: delta)) }
            case .pi:
                guard let message = record["message"] as? [String: Any], message["role"] as? String == "assistant",
                      let usage = message["usage"] as? [String: Any],
                      let timestamp = date(record["timestamp"]),
                      let id = record["id"] as? String else { continue }
                // Response IDs also deduplicate sessions copied or branched by Pi.
                let key = "pi:" + (message["provider"] as? String ?? "") + ":" + (message["responseId"] as? String ?? id)
                let total = count(usage, "totalTokens")
                result.append(TokenRecord(source: .pi, key: key, date: timestamp,
                                          tokens: total > 0 ? total : ["input", "output", "cacheRead", "cacheWrite"].reduce(0) { $0 + count(usage, $1) }))
            }
        }
        return result
    }

    /// Copies out only the lines containing `needle`, scanning the raw bytes rather than splitting the whole file.
    /// With `prefix`, only each line's first bytes are searched, which skips most of a file with long lines.
    private static func lines(in data: Data, containing needle: [UInt8], prefix: Int? = nil) -> [Data] {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return [] }
            let end = base + buffer.count
            var result: [Data] = []
            var cursor = base
            while cursor < end {
                if let prefix {
                    let stop = memchr(cursor, 10, end - cursor).map(UnsafeRawPointer.init) ?? end
                    if memmem(cursor, min(stop - cursor, prefix), needle, needle.count) != nil {
                        result.append(Data(bytes: cursor, count: stop - cursor))
                    }
                    cursor = stop + 1
                    continue
                }
                guard let found = memmem(cursor, end - cursor, needle, needle.count) else { break }
                let match = UnsafeRawPointer(found)
                var start = match
                while start > cursor, start.load(fromByteOffset: -1, as: UInt8.self) != 10 { start -= 1 }
                let stop = memchr(match, 10, end - match).map(UnsafeRawPointer.init) ?? end
                result.append(Data(bytes: start, count: stop - start))
                cursor = stop + 1
            }
            return result
        }
    }
}
