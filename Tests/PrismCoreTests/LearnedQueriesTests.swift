import XCTest
@testable import PrismCore

final class LearnedQueriesTests: XCTestCase {
    func testLatestChoiceWins() {
        var learned = LearnedQueries()
        learned.record("sfi", id: "app:safari", at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(learned.preferred(" SFI "), "app:safari")
        XCTAssertEqual(learned.boost("sfi", id: "app:safari"), 2)
        learned.record("sfi", id: "app:sf-symbols", at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(learned.preferred("sfi"), "app:sf-symbols")
        XCTAssertLessThan(learned.boost("sfi", id: "app:safari"), 1)
    }

    func testPrefixAndForget() {
        var learned = LearnedQueries()
        learned.record("safar", id: "app:safari")
        XCTAssertEqual(learned.boost("sa", id: "app:safari"), 0.15)
        XCTAssertEqual(learned.boost("x", id: "app:safari"), 0)
        XCTAssertEqual(learned.ids(for: "safar"), ["app:safari"])
        learned.forget("safar", id: "app:safari")
        XCTAssertNil(learned.preferred("safar"))
        XCTAssertEqual(learned.boost("sa", id: "app:safari"), 0)
    }

    func testCodableRoundTrip() throws {
        var learned = LearnedQueries()
        learned.record("web", id: "app:safari")
        let decoded = try JSONDecoder().decode(LearnedQueries.self, from: JSONEncoder().encode(learned))
        XCTAssertEqual(decoded, learned)
    }
}
