import Foundation

/// Parses "timer 25m tea" and "countdown 1h 30m" into a duration and a name.
public enum TimerQuery {
    public static func parse(_ query: String) -> (seconds: TimeInterval, name: String)? {
        guard let prefix = query.range(of: #"^\s*(?:timer|countdown)\s+"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var rest = String(query[prefix.upperBound...])
        var seconds: TimeInterval = 0
        let unitPattern = #"^\s*(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)?(?![a-z])"#
        while let range = rest.range(of: unitPattern, options: [.regularExpression, .caseInsensitive]) {
            let chunk = rest[range].trimmingCharacters(in: .whitespaces).lowercased()
            let number = Double(chunk.prefix { $0.isNumber || $0 == "." }) ?? 0
            let unit = chunk.drop { $0.isNumber || $0 == "." }.trimmingCharacters(in: .whitespaces)
            seconds += unit.hasPrefix("h") ? number * 3600 : unit.hasPrefix("s") ? number : number * 60
            rest = String(rest[range.upperBound...])
        }
        guard seconds >= 1, seconds <= 86400 * 2 else { return nil }
        return (seconds, rest.trimmingCharacters(in: .whitespaces))
    }

    public static func describe(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: seconds) ?? "\(Int(seconds)) seconds"
    }
}
