import XCTest
@testable import PrismCore

final class QueryParsingTests: XCTestCase {
    func testTimerQuery() {
        let tea = TimerQuery.parse("timer 25m tea")
        XCTAssertEqual(tea?.seconds, 1500)
        XCTAssertEqual(tea?.name, "tea")
        XCTAssertEqual(TimerQuery.parse("countdown 1h 30m")?.seconds, 5400)
        XCTAssertEqual(TimerQuery.parse("timer 90")?.seconds, 5400, "bare numbers are minutes")
        XCTAssertEqual(TimerQuery.parse("Timer 10 sec")?.seconds, 10)
        XCTAssertNil(TimerQuery.parse("timer tea"))
        XCTAssertNil(TimerQuery.parse("timer 3d"), "over two days is rejected")
        XCTAssertNil(TimerQuery.parse("timers 5m"))
    }

    func testDice() {
        XCTAssertEqual(Generators.dice("roll")?.count, 1)
        XCTAssertEqual(Generators.dice("roll")?.sides, 6)
        XCTAssertEqual(Generators.dice("roll d20")?.sides, 20)
        XCTAssertEqual(Generators.dice("roll 3d6")?.count, 3)
        XCTAssertNil(Generators.dice("roll 0d6"))
        XCTAssertNil(Generators.dice("roll 2d1"))
        XCTAssertNil(Generators.dice("rolls"))
    }

    func testPassword() {
        let password = Generators.password()
        XCTAssertEqual(password.count, 20)
        XCTAssertNotEqual(password, Generators.password())
    }

    func testDirectURL() {
        XCTAssertEqual(WebSearch.directURL("apple.com")?.absoluteString, "https://apple.com")
        XCTAssertEqual(WebSearch.directURL("localhost:3000/x")?.absoluteString, "http://localhost:3000/x")
        XCTAssertEqual(WebSearch.directURL("https://example.org/a?b")?.absoluteString, "https://example.org/a?b")
        XCTAssertNil(WebSearch.directURL("main.swift"))
        XCTAssertNil(WebSearch.directURL("two words.com"))
        XCTAssertNil(WebSearch.directURL("abc"))
    }

    func testSearchURLEncodesReservedCharacters() {
        let url = WebSearch.url(WebSearch.google, "a&b c")
        XCTAssertEqual(url?.absoluteString, "https://www.google.com/search?q=a%26b%20c")
    }
}

final class TextTransformTests: XCTestCase {
    func testCaseConversions() {
        XCTAssertEqual(TextTransform.camel.apply("hello world-again"), "helloWorldAgain")
        XCTAssertEqual(TextTransform.snake.apply("fooBar baz"), "foo_bar_baz")
        XCTAssertEqual(TextTransform.kebab.apply("Foo Bar"), "foo-bar")
        XCTAssertEqual(TextTransform.sentence.apply("hELLO THERE"), "Hello there")
        XCTAssertNil(TextTransform.camel.apply("  "))
    }

    func testLines() {
        XCTAssertEqual(TextTransform.sortLines.apply("b\na10\na2"), "a2\na10\nb")
        XCTAssertEqual(TextTransform.uniqueLines.apply("a\nb\na"), "a\nb")
        XCTAssertEqual(TextTransform.reverseLines.apply("1\n2\n3"), "3\n2\n1")
        XCTAssertEqual(TextTransform.trim.apply("  a  \n b \n\n"), "a\nb")
    }

    func testEncodings() {
        XCTAssertEqual(TextTransform.base64Encode.apply("hi"), "aGk=")
        XCTAssertEqual(TextTransform.base64Decode.apply(" aGk= \n"), "hi")
        XCTAssertNil(TextTransform.base64Decode.apply("%%%"))
        XCTAssertEqual(TextTransform.urlEncode.apply("a b&c"), "a%20b%26c")
        XCTAssertEqual(TextTransform.urlDecode.apply("a%20b"), "a b")
    }

    func testJSONAndCount() {
        XCTAssertEqual(TextTransform.jsonPretty.apply(#"{"b":1,"a":"x/y"}"#), "{\n  \"a\" : \"x/y\",\n  \"b\" : 1\n}")
        XCTAssertNil(TextTransform.jsonPretty.apply("{nope"))
        XCTAssertEqual(TextTransform.count.apply("one two\nthree"), "13 characters · 3 words · 2 lines")
    }
}
