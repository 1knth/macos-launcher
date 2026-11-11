import XCTest
import CoreGraphics
@testable import PrismCore

final class CalculatorTests: XCTestCase {
    func value(_ input: String) -> String? { Calculator.evaluate(input)?.display }

    func testArithmetic() {
        XCTAssertEqual(value("2+2"), "4")
        XCTAssertEqual(value("2 + 3 * 4"), "14")
        XCTAssertEqual(value("(2 + 3) * 4"), "20")
        XCTAssertEqual(value("2^10"), "1,024")
        XCTAssertEqual(value("2**3"), "8")
        XCTAssertEqual(value("-3^2"), "-9")
        XCTAssertEqual(value("0.1 + 0.2"), "0.3")
        XCTAssertEqual(value("10 / 4"), "2.5")
        XCTAssertEqual(value("1,000 * 3"), "3,000")
        XCTAssertEqual(value("5!"), "120")
        XCTAssertEqual(value("3x4"), "12")
        XCTAssertEqual(value("7 mod 3"), "1")
    }

    func testPercentages() {
        XCTAssertEqual(value("50 + 10%"), "55")
        XCTAssertEqual(value("200 - 25%"), "150")
        XCTAssertEqual(value("20% of 50"), "10")
    }

    func testFunctionsAndConstants() {
        XCTAssertEqual(value("sqrt(16)"), "4")
        XCTAssertEqual(value("max(3, 9, 2)"), "9")
        XCTAssertEqual(value("2pi"), Calculator.format(2 * .pi, grouping: true))
        XCTAssertEqual(value("sin(90deg)"), "1")
        XCTAssertEqual(value("log(1000)"), "3")
    }

    func testIgnoresPlainText() {
        XCTAssertNil(value("safari"))
        XCTAssertNil(value("42"))
        XCTAssertNil(value("2024-report"))
        XCTAssertNil(value("hello world"))
    }

    func testUnits() {
        XCTAssertEqual(value("10 km to mi"), "6.2137119224 mi")
        XCTAssertEqual(value("100 f to c"), "37.7777777778°C")
        XCTAssertEqual(value("1 GB in MB"), "1,000 MB")
        XCTAssertEqual(value("2 hours to min"), "120 min")
        XCTAssertEqual(value("5 ft in cm"), "152.4 cm")
        XCTAssertNil(value("5 kg to km"))
    }

    func testBases() {
        XCTAssertEqual(value("255 to hex"), "0xFF")
        XCTAssertEqual(value("0xff"), "255")
        XCTAssertEqual(value("10 in binary"), "0b1010")
        XCTAssertEqual(value("0b1010 + 1"), "11")
    }

    func testWorldClock() {
        let result = Calculator.evaluate("time in tokyo", now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(result?.display, "9:00 AM")
        XCTAssertNotNil(Calculator.evaluate("london time"))
        XCTAssertNil(Calculator.evaluate("time in narnia"))
    }
}

final class FuzzyTests: XCTestCase {
    func testRanking() {
        let exact = Fuzzy.score("safari", "Safari")!
        let prefix = Fuzzy.score("saf", "Safari")!
        let initials = Fuzzy.score("vsc", "Visual Studio Code")!
        let contains = Fuzzy.score("tud", "Visual Studio Code")!
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, initials)
        XCTAssertGreaterThan(initials, contains)
        XCTAssertNil(Fuzzy.score("xyz", "Safari"))
        XCTAssertNotNil(Fuzzy.score("sys set", "System Settings"))
        XCTAssertNotNil(Fuzzy.score("prefs", "System Settings", keywords: ["preferences"]))
    }

    func testWords() {
        XCTAssertEqual(Fuzzy.words("iTerm2 HelperApp"), ["i", "term", "2", "helper", "app"])
    }
}

final class OCRTests: XCTestCase {
    func testLineOrdering() {
        let lines = [
            OCRLine("world", CGRect(x: 0.5, y: 0.8, width: 0.2, height: 0.1)),
            OCRLine("hello", CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1)),
            OCRLine("second", CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.1)),
        ]
        XCTAssertEqual(TextAssembler.assemble(lines), "hello world\nsecond")
    }
}
