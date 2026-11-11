import XCTest
@testable import PrismCore

final class TokenHistoryTests: XCTestCase {
    func testPiUsageIncludesCacheAndDeduplicatesCopiedResponses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = """
        {"id":"a","timestamp":"2026-11-08T12:00:00Z","message":{"role":"assistant","provider":"openai-codex","responseId":"r1","usage":{"input":10,"output":5,"cacheRead":20,"totalTokens":35}}}
        {"id":"b","timestamp":"2026-11-08T12:00:00Z","message":{"role":"assistant","provider":"openai-codex","responseId":"r1","usage":{"totalTokens":35}}}
        {"id":"c","timestamp":"2026-11-08T12:00:00Z","message":{"role":"assistant","provider":"anthropic","usage":{"input":2,"output":3,"cacheWrite":5}}}
        """
        try Data(log.utf8).write(to: root.appendingPathComponent("pi.jsonl"))
        let missing = root.appendingPathComponent("missing")
        let days = TokenHistory.load(claudeDirectory: missing, codexDirectory: missing, piDirectory: root, since: .distantPast)
        XCTAssertEqual(days.first?.pi, 45)
        XCTAssertEqual(days.first?.codex, 0)
        XCTAssertEqual(days.first?.total, 45)
    }

    func testCacheRereadsOnlyChangedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("a.jsonl")
        let line = #"{"timestamp":"2026-11-08T12:00:00Z","message":{"id":"%@","content":"no usage here","usage":{"input_tokens":10}}}"#
        try Data(String(format: line, "one").utf8).write(to: log)
        let missing = root.appendingPathComponent("missing")
        var cache = TokenCache()
        XCTAssertEqual(TokenHistory.load(claudeDirectory: root, codexDirectory: missing, since: .distantPast, cache: &cache).first?.claude, 10)
        XCTAssertEqual(TokenHistory.load(claudeDirectory: root, codexDirectory: missing, since: .distantPast, cache: &cache).first?.claude, 10)
        try Data((String(format: line, "one") + "\n" + String(format: line, "two")).utf8).write(to: log)
        XCTAssertEqual(TokenHistory.load(claudeDirectory: root, codexDirectory: missing, since: .distantPast, cache: &cache).first?.claude, 20)
    }

    func testDeduplicatesMessagesAndCumulativeSnapshots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let claude = root.appendingPathComponent("claude")
        let codex = root.appendingPathComponent("codex")
        for directory in [claude, codex] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let claudeLog = """
        {"timestamp":"2026-11-08T12:00:00Z","message":{"id":"one","usage":{"input_tokens":10,"output_tokens":2,"cache_read_input_tokens":20}}}
        {"timestamp":"2026-11-08T12:00:00Z","message":{"id":"one","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":20}}}
        invalid
        """
        let codexLog = """
        {"timestamp":"2026-11-08T12:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}
        {"timestamp":"2026-11-08T12:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}
        {"timestamp":"2026-11-08T12:02:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":140}}}}
        """
        try Data(claudeLog.utf8).write(to: claude.appendingPathComponent("a.jsonl"))
        try Data(codexLog.utf8).write(to: codex.appendingPathComponent("b.jsonl"))
        let days = TokenHistory.load(claudeDirectory: claude, codexDirectory: codex, since: .distantPast)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.claude, 35)
        XCTAssertEqual(days.first?.codex, 140)
        XCTAssertTrue(TokenHistory.load(claudeDirectory: claude, codexDirectory: codex, since: .distantFuture).isEmpty)
    }
}
