import Foundation
import CoreFoundation

public struct UsageWindow: Identifiable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?
}

public enum UsageLimits {
    public static func resetCountdown(until reset: Date, now: Date = Date()) -> String {
        let minutes = Int(ceil(max(0, reset.timeIntervalSince(now)) / 60))
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }

    public static func parse(_ data: Data, claude: Bool) throws -> [UsageWindow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        func number(_ value: Any?) -> Double? {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        func window(_ id: String, _ title: String, _ object: Any?) -> UsageWindow? {
            guard let object = object as? [String: Any],
                  let used = number(object[claude ? "utilization" : "used_percent"]), used >= 0 else { return nil }
            var reset: Date?
            if claude, let text = object["resets_at"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                reset = formatter.date(from: text)
                if reset == nil { formatter.formatOptions = [.withInternetDateTime]; reset = formatter.date(from: text) }
            } else if let seconds = number(object["reset_at"]) { reset = Date(timeIntervalSince1970: seconds) }
            return UsageWindow(id: id, title: title, usedPercent: used, resetsAt: reset)
        }
        if claude {
            return [("five_hour", "Session · 5 hours"), ("seven_day", "Weekly · All models"),
                    ("seven_day_sonnet", "Weekly · Sonnet"), ("seven_day_opus", "Weekly · Opus")]
                .compactMap { window($0.0, $0.1, root[$0.0]) }
        }
        let limits = root["rate_limit"] as? [String: Any] ?? [:]
        return [("primary_window", "Primary"), ("secondary_window", "Secondary")].compactMap { key, title in
            let object = limits[key] as? [String: Any]
            let seconds = number(object?["limit_window_seconds"])
            let label = seconds.map { $0 == 604800 ? "Weekly" : $0 == 18000 ? "5 hours" : "\(Int($0 / 60)) minutes" } ?? title
            return window(key, label, object)
        }
    }
}
