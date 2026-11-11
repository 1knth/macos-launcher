import Foundation

/// Search keywords ("g swift", "yt lofi") and text that should open as a URL.
public enum WebSearch {
    public struct Engine {
        public let keyword: String
        public let name: String
        public let template: String
        public let symbol: String
    }

    public static let engines: [Engine] = [
        Engine(keyword: "g", name: "Google", template: "https://www.google.com/search?q=%@", symbol: "magnifyingglass"),
        Engine(keyword: "ddg", name: "DuckDuckGo", template: "https://duckduckgo.com/?q=%@", symbol: "magnifyingglass"),
        Engine(keyword: "yt", name: "YouTube", template: "https://www.youtube.com/results?search_query=%@", symbol: "play.rectangle.fill"),
        Engine(keyword: "gh", name: "GitHub", template: "https://github.com/search?q=%@", symbol: "chevron.left.forwardslash.chevron.right"),
        Engine(keyword: "wiki", name: "Wikipedia", template: "https://en.wikipedia.org/wiki/Special:Search?search=%@", symbol: "book.closed.fill"),
        Engine(keyword: "maps", name: "Apple Maps", template: "maps://?q=%@", symbol: "map.fill"),
        Engine(keyword: "npm", name: "npm", template: "https://www.npmjs.com/search?q=%@", symbol: "shippingbox.fill"),
        Engine(keyword: "so", name: "Stack Overflow", template: "https://stackoverflow.com/search?q=%@", symbol: "text.bubble.fill"),
        Engine(keyword: "r", name: "Reddit", template: "https://www.reddit.com/search/?q=%@", symbol: "bubble.left.and.bubble.right.fill"),
    ]

    public static var google: Engine { engines[0] }

    public static func url(_ engine: Engine, _ text: String) -> URL? {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? text
        return URL(string: engine.template.replacingOccurrences(of: "%@", with: encoded))
    }

    /// Treats "apple.com", "localhost:3000" or "https://…" as something to open directly.
    public static func directURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(" "), trimmed.count > 3 else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()), url.host != nil { return url }
        if trimmed.range(of: #"^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?(/.*)?$"#, options: .regularExpression) != nil { return URL(string: "http://" + trimmed) }
        if trimmed.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(:\d+)?(/.*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil,
           !trimmed.hasSuffix(".app"), !trimmed.hasSuffix(".swift"), !trimmed.hasSuffix(".txt") { return URL(string: "https://" + trimmed) }
        return nil
    }
}
