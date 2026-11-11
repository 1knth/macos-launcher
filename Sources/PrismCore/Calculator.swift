import Foundation

/// Inline calculator for the root search: arithmetic, percentages, functions,
/// unit conversion ("5 km to mi"), number bases ("255 to hex") and world clocks ("time in tokyo").
public enum Calculator {
    public struct Result: Equatable {
        /// Display text, e.g. "1,234.5" or "6.214 mi".
        public let display: String
        /// Text placed on the clipboard (no grouping separators).
        public let copy: String
        /// Short caption, e.g. "Length" or "Asia/Tokyo".
        public let detail: String
    }

    public static func evaluate(_ raw: String, now: Date = Date()) -> Result? {
        let input = raw.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty, input.count < 300 else { return nil }
        if let clock = worldClock(input, now: now) { return clock }
        if let converted = convert(input) { return converted }
        if let based = baseConversion(input) { return based }
        guard looksLikeMath(input) else { return nil }
        var parser = Parser(input)
        guard let value = parser.parse(), value.isFinite else { return nil }
        return Result(display: format(value, grouping: true), copy: format(value, grouping: false), detail: "Calculator")
    }

    // MARK: Formatting

    public static func format(_ value: Double, grouping: Bool) -> String {
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            return String(format: "%.6g", value).replacingOccurrences(of: "e+", with: "e")
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.maximumFractionDigits = magnitude >= 1 ? 10 : 12
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if grouping { formatter.groupingSeparator = ","; formatter.groupingSize = 3 }
        // Trim binary floating point noise such as 0.1 + 0.2.
        let rounded = Double(String(format: "%.12g", value)) ?? value
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(value)"
    }

    static func looksLikeMath(_ input: String) -> Bool {
        let lowered = input.lowercased()
        if lowered.hasPrefix("0x") || lowered.hasPrefix("0b") || lowered.hasPrefix("0o") { return true }
        let operators = CharacterSet(charactersIn: "+-*/^%×÷!()")
        let digits = lowered.rangeOfCharacter(from: .decimalDigits) != nil
        if lowered.firstMatch(#"^[\d.]+\s*x\s*[\d.]+$"#) != nil { return true }
        if lowered.unicodeScalars.dropFirst().contains(where: operators.contains) && digits { return true }
        let functions = ["sqrt", "sin", "cos", "tan", "log", "ln", "abs", "pi", "π", "round", "floor", "ceil", "exp", "cbrt", " of ", " mod "]
        return functions.contains { lowered.contains($0) } && (digits || lowered.contains("pi") || lowered.contains("π"))
    }

    // MARK: Units

    struct Unit {
        let category: String
        let factor: Double
        let symbol: String
    }

    static let units: [String: Unit] = {
        var table: [String: Unit] = [:]
        func add(_ category: String, _ factor: Double, _ symbol: String, _ aliases: [String]) {
            let unit = Unit(category: category, factor: factor, symbol: symbol)
            for alias in aliases + [symbol] { table[alias.lowercased()] = unit }
        }
        add("Length", 0.001, "mm", ["millimeter", "millimeters", "millimetre", "millimetres"])
        add("Length", 0.01, "cm", ["centimeter", "centimeters", "centimetre", "centimetres"])
        add("Length", 1, "m", ["meter", "meters", "metre", "metres"])
        add("Length", 1000, "km", ["kilometer", "kilometers", "kilometre", "kilometres", "kms"])
        add("Length", 0.0254, "in", ["inch", "inches", "\""])
        add("Length", 0.3048, "ft", ["foot", "feet", "'"])
        add("Length", 0.9144, "yd", ["yard", "yards"])
        add("Length", 1609.344, "mi", ["mile", "miles"])
        add("Length", 1852, "nmi", ["nautical mile", "nautical miles"])
        add("Mass", 0.000001, "mg", ["milligram", "milligrams"])
        add("Mass", 0.001, "g", ["gram", "grams"])
        add("Mass", 1, "kg", ["kilogram", "kilograms", "kilo", "kilos", "kgs"])
        add("Mass", 1000, "t", ["tonne", "tonnes", "ton", "tons"])
        add("Mass", 0.028349523125, "oz", ["ounce", "ounces"])
        add("Mass", 0.45359237, "lb", ["lbs", "pound", "pounds"])
        add("Mass", 6.35029318, "st", ["stone", "stones"])
        add("Volume", 0.001, "ml", ["milliliter", "milliliters", "millilitre", "millilitres"])
        add("Volume", 1, "l", ["liter", "liters", "litre", "litres"])
        add("Volume", 3.785411784, "gal", ["gallon", "gallons"])
        add("Volume", 0.946352946, "qt", ["quart", "quarts"])
        add("Volume", 0.473176473, "pt", ["pint", "pints"])
        add("Volume", 0.2365882365, "cup", ["cups"])
        add("Volume", 0.0295735295625, "fl oz", ["floz", "fluid ounce", "fluid ounces"])
        add("Volume", 0.01478676478125, "tbsp", ["tablespoon", "tablespoons"])
        add("Volume", 0.00492892159375, "tsp", ["teaspoon", "teaspoons"])
        add("Time", 0.001, "ms", ["millisecond", "milliseconds"])
        add("Time", 1, "s", ["sec", "secs", "second", "seconds"])
        add("Time", 60, "min", ["mins", "minute", "minutes"])
        add("Time", 3600, "h", ["hr", "hrs", "hour", "hours"])
        add("Time", 86400, "d", ["day", "days"])
        add("Time", 604800, "wk", ["week", "weeks"])
        add("Time", 2629746, "mo", ["month", "months"])
        add("Time", 31556952, "yr", ["year", "years"])
        add("Data", 0.125, "bit", ["bits"])
        add("Data", 1, "B", ["byte", "bytes"])
        add("Data", 1e3, "KB", ["kilobyte", "kilobytes"])
        add("Data", 1e6, "MB", ["megabyte", "megabytes"])
        add("Data", 1e9, "GB", ["gigabyte", "gigabytes"])
        add("Data", 1e12, "TB", ["terabyte", "terabytes"])
        add("Data", 1024, "KiB", ["kibibyte"])
        add("Data", 1_048_576, "MiB", ["mebibyte"])
        add("Data", 1_073_741_824, "GiB", ["gibibyte"])
        add("Data", 1_099_511_627_776, "TiB", ["tebibyte"])
        add("Speed", 1, "m/s", ["mps"])
        add("Speed", 1 / 3.6, "km/h", ["kph", "kmh"])
        add("Speed", 0.44704, "mph", [])
        add("Speed", 0.514444, "kn", ["knot", "knots"])
        add("Area", 1, "m²", ["m2", "sqm"])
        add("Area", 1e6, "km²", ["km2"])
        add("Area", 0.09290304, "ft²", ["ft2", "sqft"])
        add("Area", 4046.8564224, "ac", ["acre", "acres"])
        add("Area", 10000, "ha", ["hectare", "hectares"])
        return table
    }()

    static let temperatures: [String: String] = [
        "c": "°C", "°c": "°C", "celsius": "°C", "degc": "°C",
        "f": "°F", "°f": "°F", "fahrenheit": "°F", "degf": "°F",
        "k": "K", "kelvin": "K",
    ]

    static func convert(_ input: String) -> Result? {
        let pattern = #"^(.+?)\s*([a-zA-Z°²/"' ]+?)\s+(?:to|in|as|=|->)\s+([a-zA-Z°²/ ]+)$"#
        guard let match = input.firstMatch(pattern) else { return nil }
        let expression = match[1], fromName = match[2].lowercased(), toName = match[3].lowercased().trimmingCharacters(in: .whitespaces)
        var parser = Parser(expression)
        guard let value = parser.parse() else { return nil }
        if let from = temperatures[fromName], let to = temperatures[toName] {
            let kelvin: Double
            switch from {
            case "°C": kelvin = value + 273.15
            case "°F": kelvin = (value - 32) * 5 / 9 + 273.15
            default: kelvin = value
            }
            let result: Double
            switch to {
            case "°C": result = kelvin - 273.15
            case "°F": result = (kelvin - 273.15) * 9 / 5 + 32
            default: result = kelvin
            }
            return unitResult(result, symbol: to, category: "Temperature")
        }
        let fromKey = fromName == "b" ? "B" : fromName, toKey = toName == "b" ? "B" : toName
        guard let from = units[fromKey.lowercased()] ?? units[fromKey], let to = units[toKey.lowercased()] ?? units[toKey],
              from.category == to.category else { return nil }
        return unitResult(value * from.factor / to.factor, symbol: to.symbol, category: from.category)
    }

    static func unitResult(_ value: Double, symbol: String, category: String) -> Result {
        let separator = symbol.hasPrefix("°") ? "" : " "
        return Result(display: format(value, grouping: true) + separator + symbol, copy: format(value, grouping: false), detail: category)
    }

    // MARK: Bases

    static func baseConversion(_ input: String) -> Result? {
        guard let match = input.firstMatch(#"^(.+?)\s+(?:to|in|as)\s+(hex|hexadecimal|bin|binary|oct|octal|dec|decimal)$"#) else { return nil }
        var parser = Parser(match[1])
        guard let value = parser.parse(), value.isFinite, value.rounded() == value, abs(value) < 9.2e18 else { return nil }
        let integer = Int64(value)
        let text: String
        switch match[2].lowercased() {
        case "hex", "hexadecimal": text = "0x" + String(integer, radix: 16).uppercased()
        case "bin", "binary": text = "0b" + String(integer, radix: 2)
        case "oct", "octal": text = "0o" + String(integer, radix: 8)
        default: text = String(integer)
        }
        return Result(display: text, copy: text, detail: "Number Base")
    }

    // MARK: World clock

    static func worldClock(_ input: String, now: Date) -> Result? {
        let lowered = input.lowercased()
        let place: String
        if let match = lowered.firstMatch(#"^(?:time|clock)\s+(?:in|at)\s+(.+)$"#) {
            place = match[1]
        } else if let match = lowered.firstMatch(#"^(.+?)\s+time$"#) {
            place = match[1]
        } else { return nil }
        guard let zone = timeZone(named: place.trimmingCharacters(in: .whitespaces)) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = zone
        formatter.dateFormat = "h:mm a"
        let time = formatter.string(from: now)
        formatter.dateFormat = "EEE, MMM d"
        let day = formatter.string(from: now)
        let offset = zone.secondsFromGMT(for: now) / 60
        let gmt = String(format: "GMT%@%d", offset >= 0 ? "+" : "-", abs(offset) / 60) + (offset % 60 == 0 ? "" : String(format: ":%02d", abs(offset) % 60))
        return Result(display: time, copy: "\(time) \(day)", detail: "\(day) · \(zone.identifier.replacingOccurrences(of: "_", with: " ")) (\(gmt))")
    }

    static let cityAliases: [String: String] = [
        "nyc": "America/New_York", "new york": "America/New_York", "sf": "America/Los_Angeles",
        "san francisco": "America/Los_Angeles", "la": "America/Los_Angeles", "seattle": "America/Los_Angeles",
        "boston": "America/New_York", "miami": "America/New_York", "austin": "America/Chicago",
        "beijing": "Asia/Shanghai", "delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "india": "Asia/Kolkata",
        "japan": "Asia/Tokyo", "uk": "Europe/London", "england": "Europe/London", "germany": "Europe/Berlin",
        "france": "Europe/Paris", "korea": "Asia/Seoul", "china": "Asia/Shanghai", "australia": "Australia/Sydney",
        "ottawa": "America/Toronto", "montreal": "America/Toronto", "waterloo": "America/Toronto",
        "hawaii": "Pacific/Honolulu", "dubai": "Asia/Dubai", "hk": "Asia/Hong_Kong",
    ]

    static func timeZone(named place: String) -> TimeZone? {
        if let alias = cityAliases[place] { return TimeZone(identifier: alias) }
        if place.count <= 4, let zone = TimeZone(abbreviation: place.uppercased()) { return zone }
        let normalized = place.replacingOccurrences(of: " ", with: "_")
        let identifiers = TimeZone.knownTimeZoneIdentifiers
        let city = identifiers.first { $0.split(separator: "/").last?.lowercased() == normalized }
            ?? identifiers.first { $0.split(separator: "/").last?.lowercased().hasPrefix(normalized) == true && normalized.count >= 3 }
        return city.flatMap(TimeZone.init(identifier:))
    }
}

// MARK: - Expression parser

/// Recursive-descent parser:
///   expr    := term (("+" | "-") term)*      — "50 + 10%" means 55
///   term    := unary (("*" | "/" | "mod" | implicit) unary)*
///   unary   := ("-" | "+") unary | power
///   power   := postfix ("^" unary)?
///   postfix := primary ("%" | "!")*
///   primary := number | function "(" args ")" | constant | "(" expr ")"
struct Parser {
    enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case symbol(Character)
    }

    private var tokens: [Token] = []
    private var position = 0
    private var valid = true

    init(_ input: String) {
        tokens = Parser.tokenize(input) ?? []
        valid = !tokens.isEmpty
    }

    mutating func parse() -> Double? {
        guard valid, let value = expression() else { return nil }
        return position == tokens.count ? value.value : nil
    }

    static func tokenize(_ input: String) -> [Token]? {
        var tokens: [Token] = []
        let characters = Array(input.lowercased())
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }
            if character == "0", index + 1 < characters.count, "xbo".contains(characters[index + 1]) {
                let radix = characters[index + 1] == "x" ? 16 : characters[index + 1] == "b" ? 2 : 8
                var end = index + 2
                while end < characters.count, characters[end].isHexDigit { end += 1 }
                guard end > index + 2, let value = Int64(String(characters[(index + 2)..<end]), radix: radix) else { return nil }
                tokens.append(.number(Double(value)))
                index = end
                continue
            }
            if character.isNumber || character == "." {
                var end = index
                var text = ""
                while end < characters.count, characters[end].isNumber || characters[end] == "." || characters[end] == "_"
                        || (characters[end] == "," && Parser.isThousandsGroup(characters, end)) {
                    if characters[end] != "_" && characters[end] != "," { text.append(characters[end]) }
                    end += 1
                }
                if end < characters.count, characters[end] == "e", end + 1 < characters.count,
                   characters[end + 1].isNumber || ((characters[end + 1] == "-" || characters[end + 1] == "+") && end + 2 < characters.count && characters[end + 2].isNumber) {
                    text.append("e")
                    end += 1
                    if !characters[end].isNumber { text.append(characters[end]); end += 1 }
                    while end < characters.count, characters[end].isNumber { text.append(characters[end]); end += 1 }
                }
                guard let value = Double(text) else { return nil }
                tokens.append(.number(value))
                index = end
                continue
            }
            if character == "π" { tokens.append(.identifier("pi")); index += 1; continue }
            if character == "x", case .number = tokens.last, index + 1 < characters.count, characters[index + 1].isNumber {
                tokens.append(.symbol("*")); index += 1; continue
            }
            if character.isLetter {
                var end = index
                while end < characters.count, characters[end].isLetter || characters[end].isNumber && end > index { end += 1 }
                let word = String(characters[index..<end])
                // "3x4" reads as multiplication.
                if word == "x", case .number = tokens.last { tokens.append(.symbol("*")) } else if word == "of" { tokens.append(.symbol("*")) } else { tokens.append(.identifier(word)) }
                index = end
                continue
            }
            switch character {
            case "×", "∙", "·": tokens.append(.symbol("*"))
            case "÷": tokens.append(.symbol("/"))
            case "−": tokens.append(.symbol("-"))
            case "*" where index + 1 < characters.count && characters[index + 1] == "*":
                tokens.append(.symbol("^")); index += 1
            case "+", "-", "*", "/", "^", "%", "(", ")", "!", ",": tokens.append(.symbol(character))
            default: return nil
            }
            index += 1
        }
        return tokens
    }

    static func isThousandsGroup(_ characters: [Character], _ comma: Int) -> Bool {
        guard comma + 3 < characters.count else { return false }
        guard characters[(comma + 1)...(comma + 3)].allSatisfy(\.isNumber) else { return false }
        return comma + 4 == characters.count || !characters[comma + 4].isNumber
    }

    struct Value { var value: Double; var percent = false }

    private var current: Token? { position < tokens.count ? tokens[position] : nil }
    private mutating func advance() { position += 1 }

    private mutating func expression() -> Value? {
        guard var left = term() else { return nil }
        while let token = current, token == .symbol("+") || token == .symbol("-") {
            advance()
            guard let right = term() else { return nil }
            let sign: Double = token == .symbol("+") ? 1 : -1
            left = Value(value: right.percent ? left.value * (1 + sign * right.value) : left.value + sign * right.value)
        }
        return left
    }

    private mutating func term() -> Value? {
        guard var left = unary() else { return nil }
        while let token = current {
            if token == .symbol("*") || token == .symbol("/") || token == .identifier("mod") {
                advance()
                guard let right = unary() else { return nil }
                switch token {
                case .symbol("*"): left = Value(value: left.value * right.value)
                case .symbol("/"): left = Value(value: left.value / right.value)
                default: left = Value(value: left.value.truncatingRemainder(dividingBy: right.value))
                }
            } else if startsOperand(token) {
                // Implicit multiplication: "2pi", "3(4+1)".
                guard let right = unary() else { return nil }
                left = Value(value: left.value * right.value)
            } else { break }
        }
        return left
    }

    private func startsOperand(_ token: Token) -> Bool {
        switch token {
        case .number: return true
        case .identifier(let name): return name != "mod"
        case .symbol(let symbol): return symbol == "("
        }
    }

    private mutating func unary() -> Value? {
        if current == .symbol("-") { advance(); return unary().map { Value(value: -$0.value, percent: $0.percent) } }
        if current == .symbol("+") { advance(); return unary() }
        return power()
    }

    private mutating func power() -> Value? {
        guard let base = postfix() else { return nil }
        if current == .symbol("^") {
            advance()
            guard let exponent = unary() else { return nil }
            return Value(value: pow(base.value, exponent.value))
        }
        return base
    }

    private mutating func postfix() -> Value? {
        guard var value = primary() else { return nil }
        while let token = current {
            if token == .symbol("%") {
                advance()
                value = Value(value: value.value / 100, percent: true)
            } else if token == .symbol("!") {
                advance()
                guard value.value >= 0, value.value <= 170, value.value.rounded() == value.value else { return nil }
                value = Value(value: (1...max(1, Int(value.value))).reduce(1.0) { $0 * Double($1) })
            } else { break }
        }
        return value
    }

    private static let constants: [String: Double] = ["pi": .pi, "e": M_E, "tau": 2 * .pi, "phi": (1 + sqrt(5)) / 2, "deg": .pi / 180]
    private static let functions: [String: ([Double]) -> Double?] = [
        "sqrt": { $0.count == 1 ? sqrt($0[0]) : nil }, "cbrt": { $0.count == 1 ? cbrt($0[0]) : nil },
        "sin": { $0.count == 1 ? sin($0[0]) : nil }, "cos": { $0.count == 1 ? cos($0[0]) : nil },
        "tan": { $0.count == 1 ? tan($0[0]) : nil }, "asin": { $0.count == 1 ? asin($0[0]) : nil },
        "acos": { $0.count == 1 ? acos($0[0]) : nil }, "atan": { $0.count == 1 ? atan($0[0]) : nil },
        "log": { $0.count == 1 ? log10($0[0]) : $0.count == 2 ? log($0[1]) / log($0[0]) : nil },
        "ln": { $0.count == 1 ? log($0[0]) : nil }, "log2": { $0.count == 1 ? log2($0[0]) : nil },
        "exp": { $0.count == 1 ? exp($0[0]) : nil }, "abs": { $0.count == 1 ? abs($0[0]) : nil },
        "round": { $0.count == 1 ? $0[0].rounded() : nil }, "floor": { $0.count == 1 ? floor($0[0]) : nil },
        "ceil": { $0.count == 1 ? ceil($0[0]) : nil }, "min": { $0.isEmpty ? nil : $0.min() },
        "max": { $0.isEmpty ? nil : $0.max() }, "pow": { $0.count == 2 ? pow($0[0], $0[1]) : nil },
    ]

    private mutating func primary() -> Value? {
        guard let token = current else { return nil }
        switch token {
        case .number(let value):
            advance()
            return Value(value: value)
        case .symbol("("):
            advance()
            guard let inner = expression(), current == .symbol(")") else { return nil }
            advance()
            return inner
        case .identifier(let name):
            advance()
            if let function = Parser.functions[name] {
                if current == .symbol("(") {
                    advance()
                    var arguments: [Double] = []
                    if current != .symbol(")") {
                        guard let first = expression() else { return nil }
                        arguments.append(first.value)
                        while current == .symbol(",") {
                            advance()
                            guard let next = expression() else { return nil }
                            arguments.append(next.value)
                        }
                    }
                    guard current == .symbol(")") else { return nil }
                    advance()
                    return function(arguments).map { Value(value: $0) }
                }
                // "sqrt 16"
                guard let argument = power() else { return nil }
                return function([argument.value]).map { Value(value: $0) }
            }
            return Parser.constants[name].map { Value(value: $0) }
        default:
            return nil
        }
    }
}

extension String {
    func firstMatch(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: self).map { String(self[$0]) } ?? ""
        }
    }
}
