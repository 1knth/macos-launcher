import XCTest
@testable import PrismCore

final class UsageLimitsTests: XCTestCase {
    func testResetCountdownUsesOnlyHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(UsageLimits.resetCountdown(until: now.addingTimeInterval(2794), now: now), "47m")
        XCTAssertEqual(UsageLimits.resetCountdown(until: now.addingTimeInterval(5460), now: now), "1h 31m")
        XCTAssertEqual(UsageLimits.resetCountdown(until: now.addingTimeInterval(432000), now: now), "120h 0m")
        XCTAssertEqual(UsageLimits.resetCountdown(until: now.addingTimeInterval(-1), now: now), "0m")
    }

    func testClaudeWindowsAndFractionalReset() throws {
        let data = Data(#"{"five_hour":{"utilization":42.5,"resets_at":"2026-11-04T20:00:00.000Z"},"seven_day":null,"seven_day_sonnet":{"utilization":0}}"#.utf8)
        let windows = try UsageLimits.parse(data, claude: true)
        XCTAssertEqual(windows.map(\.usedPercent), [42.5, 0])
        XCTAssertNotNil(windows.first?.resetsAt)
        XCTAssertNil(windows.last?.resetsAt)
    }

    func testCodexWindows() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":100,"reset_at":1793822400,"limit_window_seconds":18000},"secondary_window":{"used_percent":12,"limit_window_seconds":604800}}}"#.utf8)
        let windows = try UsageLimits.parse(data, claude: false)
        XCTAssertEqual(windows.map(\.title), ["5 hours", "Weekly"])
        XCTAssertEqual(windows.first?.usedPercent, 100)
        XCTAssertEqual(windows.first?.resetsAt, Date(timeIntervalSince1970: 1793822400))
    }

    func testInvalidValuesAreNotReportedAsZero() throws {
        for value in ["null", "true", "\"10\"", "-1"] {
            let data = Data("{\"five_hour\":{\"utilization\":\(value)},\"seven_day\":{\"utilization\":20}}".utf8)
            XCTAssertEqual(try UsageLimits.parse(data, claude: true).map(\.usedPercent), [20])
        }
        // Over the limit is still a window to show, not invalid data.
        XCTAssertEqual(try UsageLimits.parse(Data(#"{"five_hour":{"utilization":104}}"#.utf8), claude: true).map(\.usedPercent), [104])
        XCTAssertTrue(try UsageLimits.parse(Data("{}".utf8), claude: false).isEmpty)
        XCTAssertThrowsError(try UsageLimits.parse(Data("invalid".utf8), claude: true))
    }
}
