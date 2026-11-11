import AppKit
import PrismCore
import UserNotifications

/// Countdown timers started with "timer 25m tea".
final class TimerManager {
    struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let end: Date
        let timer: Timer
    }

    private(set) var entries: [Entry] = []
    var onChange: (() -> Void)?

    func start(seconds: TimeInterval, name: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let label = name.isEmpty ? TimerQuery.describe(seconds) + " timer" : name
        var entryID: UUID?
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, let id = entryID else { return }
            self.finish(id)
        }
        let entry = Entry(name: label, end: Date().addingTimeInterval(seconds), timer: timer)
        entryID = entry.id
        entries.append(entry)
        onChange?()
        Toast.show("Timer started: \(label)", symbol: "timer", tint: .systemOrange)
    }

    func cancel(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].timer.invalidate()
        entries.remove(at: index)
        onChange?()
    }

    private func finish(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        onChange?()
        NSSound(named: "Glass")?.play()
        Toast.show("⏰  \(entry.name) is done", symbol: "alarm.fill", tint: .systemOrange, duration: 6)
        let content = UNMutableNotificationContent()
        content.title = "Timer finished"
        content.body = entry.name
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: nil))
    }
}
