import AppKit
import Combine
import PrismCore
import SwiftUI

/// The home search. With no query it shows running timers, selected-text actions, recently and
/// often used items and suggestions. With a query, sections appear in this order:
/// timers, calculator, query-shaped quick results, ranked apps and commands, files, then fallbacks.
final class RootResults: ResultProvider {
    private unowned let navigator: LauncherNavigator
    private let services: AppServices
    private let commands: CommandCatalog
    private let selection: SelectionResults
    private let files = FileSearcher()
    private var appUpdates: AnyCancellable?

    private static let suggested = ["nav.chat", "nav.clipboard", "nav.files", "nav.windows", "ocr.capture", "color.pick", "nav.wheel", "nav.emoji", "sys.awake", "window.leftHalf"]

    init(services: AppServices, commands: CommandCatalog, selection: SelectionResults, navigator: LauncherNavigator) {
        self.services = services
        self.commands = commands
        self.selection = selection
        self.navigator = navigator
        let refreshIfShowing = { [weak navigator] in
            if navigator?.route == .root { navigator?.refresh(keepSelection: true) }
        }
        files.onUpdate = refreshIfShowing
        services.timers.onChange = refreshIfShowing
        appUpdates = services.apps.$apps.dropFirst().sink { _ in
            // @Published emits before `apps` changes; refresh after the new index is stored.
            DispatchQueue.main.async(execute: refreshIfShowing)
        }
    }

    func deactivate() { files.stop() }

    func items(for raw: String) -> [ResultItem] {
        let query = raw.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            files.stop()
            return timerItems() + selection.items() + usedAndSuggestedItems()
        }
        // "g" alone is the shortcut into Google search, not a search for "g".
        if query.lowercased() == "g" {
            files.stop()
            return [singleActionItem("nav.google", "Search Google", "magnifyingglass", .blue, section: "Web", dismiss: false) { [weak navigator] in
                navigator?.push(.google)
            }]
        }
        var output = timerItems()
        if let calculation = calculatorItem(query) { output.append(calculation) }
        output += quickItems(query)
        output += rankedItems(query)
        output += fileItems(query)
        output += fallbackItems(query)
        return output
    }

    // MARK: Empty query

    private func usedAndSuggestedItems() -> [ResultItem] {
        let commandList = commands.all()
        // Rank IDs first and build items only for the picks; each app item looks up its running app.
        let appsByID = Dictionary(services.apps.apps.map { (Self.appID($0), $0) }, uniquingKeysWith: { first, _ in first })
        let commandsByID = Dictionary(commandList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func make(_ id: String, _ section: String) -> ResultItem? {
            appsByID[id].map { appItem($0, section: section) } ?? commandsByID[id].map { commands.item(for: $0, section: section) }
        }
        let ids = Set(appsByID.keys).union(commandsByID.keys)
        let frecency = services.frecency
        let last = frecency.last(among: ids)
        let lastItems = last.flatMap { make($0, "Last Used") }.map { [$0] } ?? []
        let mostUsed = frecency.mostUsed(6, among: ids.subtracting(last.map { [$0] } ?? [])).compactMap { make($0, "Most Used") }
        let recent = lastItems + mostUsed
        let suggestions = Self.suggested
            .filter { id in !recent.contains { $0.id == id } }
            .compactMap { commandsByID[$0] }
            .map { commands.item(for: $0, section: "Suggestions") }
        return recent + suggestions
    }

    // MARK: Query sections

    private func calculatorItem(_ query: String) -> ResultItem? {
        guard let result = Calculator.evaluate(query) else { return nil }
        return ResultItem(
            id: "calc", title: result.display, icon: .symbol("equal", .orange), section: "Calculator",
            actions: [
                ItemAction(title: "Copy Answer", symbol: "doc.on.doc", shortcut: .enter) {
                    Paster.copy(result.copy)
                    Toast.show("Copied \(result.copy)", symbol: "equal.circle.fill", tint: .systemOrange)
                },
                ItemAction(title: "Paste Answer", symbol: "doc.on.clipboard", shortcut: .cmdEnter) {
                    Paster.copy(result.copy)
                    Paster.pasteIntoFrontApp()
                },
                ItemAction(title: "Copy Expression and Answer", symbol: "text.append", shortcut: .cmdShift("c")) {
                    Paster.copy("\(query) = \(result.copy)")
                },
            ],
            style: .calculator(expression: query, result: result.display, detail: result.detail)
        )
    }

    /// Inline items driven by the query's shape: web search keywords, URLs, timers, dice, quit.
    private func quickItems(_ query: String) -> [ResultItem] {
        var items: [ResultItem] = []
        let parts = query.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, let engine = WebSearch.engines.first(where: { $0.keyword == parts[0].lowercased() }) {
            let text = parts[1]
            items.append(ResultItem(
                id: "web.\(engine.keyword)", title: "Search \(engine.name) for “\(text)”", icon: .symbol(engine.symbol, .blue),
                accessory: engine.keyword, section: "Web",
                actions: [ItemAction(title: "Open in Browser", symbol: "safari", shortcut: .enter) {
                    if let url = WebSearch.url(engine, text) { NSWorkspace.shared.open(url) }
                }]
            ))
        }
        if let url = WebSearch.directURL(query) {
            items.append(ResultItem(
                id: "web.url", title: "Open \(url.absoluteString)", icon: .symbol("safari.fill", .blue), section: "Web",
                actions: [
                    ItemAction(title: "Open in Browser", symbol: "safari", shortcut: .enter) { NSWorkspace.shared.open(url) },
                    ItemAction(title: "Copy URL", symbol: "link", shortcut: .cmdShift("c")) { Paster.copy(url.absoluteString) },
                ]
            ))
        }
        if let timer = TimerQuery.parse(query) {
            let timers = services.timers
            items.append(ResultItem(
                id: "timer.new", title: "Start \(TimerQuery.describe(timer.seconds)) Timer", subtitle: timer.name.isEmpty ? nil : timer.name,
                icon: .symbol("timer", .orange), accessory: "Timer", section: "Timers",
                actions: [ItemAction(title: "Start Timer", symbol: "play.fill", shortcut: .enter) {
                    timers.start(seconds: timer.seconds, name: timer.name)
                }]
            ))
        }
        if let dice = Generators.dice(query) {
            items.append(ResultItem(
                id: "dice", title: "Roll \(dice.count)d\(dice.sides)", icon: .symbol("dice.fill", .red), accessory: "Fun", section: "Fun",
                actions: [ItemAction(title: "Roll", symbol: "dice", shortcut: .enter, dismiss: false) { [weak navigator] in
                    let rolls = (0..<dice.count).map { _ in Int.random(in: 1...dice.sides) }
                    let total = rolls.reduce(0, +)
                    navigator?.flash(rolls.count > 1 ? "🎲  \(rolls.map(String.init).joined(separator: " + ")) = \(total)" : "🎲  \(total)", symbol: "dice.fill")
                }]
            ))
        }
        if parts.count == 2, ["quit", "kill"].contains(parts[0].lowercased()) {
            let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            for app in running {
                guard let name = app.localizedName, Fuzzy.score(parts[1], name) != nil else { continue }
                items.append(ResultItem(
                    id: "quit.\(app.processIdentifier)", title: "Quit \(name)", icon: app.bundleURL.map { .file($0.path) } ?? .symbol("xmark", .red),
                    accessory: "Running", section: "Running Apps",
                    actions: [
                        ItemAction(title: "Quit", symbol: "xmark.circle", shortcut: .enter) { app.terminate() },
                        ItemAction(title: "Force Quit", symbol: "bolt.slash", shortcut: .cmdEnter, destructive: true) { app.forceTerminate() },
                    ]
                ))
            }
        }
        return items
    }

    /// Apps and commands scored by fuzzy match, frecency and learned queries; the top 10 are shown.
    private func rankedItems(_ query: String) -> [ResultItem] {
        let learned = services.learned.queries
        let frecency = services.frecency
        // Learned picks match even when fuzzy matching wouldn't, so aliases like "web" → Safari work.
        let aliased = learned.ids(for: query)
        func score(_ id: String, _ title: String, _ keywords: [String]) -> Double? {
            guard let match = Fuzzy.score(query, title, keywords: keywords) ?? (aliased.contains(id) ? 0 : nil) else { return nil }
            return match + frecency.boost(id) + learned.boost(query, id: id)
        }
        var ranked: [(ResultItem, Double)] = []
        for app in services.apps.apps {
            guard let score = score(Self.appID(app), app.name, app.keywords) else { continue }
            ranked.append((withForget(appItem(app, section: "Results"), query: query), score))
        }
        for command in commands.all() {
            guard let score = score(command.id, command.title, command.keywords) else { continue }
            // Apps edge out commands on ties, as people mostly launch apps.
            ranked.append((withForget(commands.item(for: command, section: "Results"), query: query), score - 0.02))
        }
        return ranked.sorted { $0.1 > $1.1 }.prefix(10).map(\.0)
    }

    private func fileItems(_ query: String) -> [ResultItem] {
        guard query.count >= 2 else { return [] }
        files.search(query, limit: 5, recentWhenEmpty: false)
        return files.results.map { url in
            FileResults.item(url, section: "Files", navigator: navigator) { [weak self] in self?.files.stop() }
        }
    }

    /// "Use “query” with…": hand the query to another route or the web.
    private func fallbackItems(_ query: String) -> [ResultItem] {
        let section = "Use “\(query.count > 24 ? String(query.prefix(24)) + "…" : query)” with…"
        func open(_ route: Route, _ id: String, _ title: String, _ symbol: String, _ color: Color) -> ResultItem {
            singleActionItem(id, title, symbol, color, section: section, dismiss: false) { [weak navigator] in
                navigator?.push(route, query: query)
            }
        }
        return [
            open(.chat, "fallback.ai", "Ask Luna", "sparkles", .indigo),
            singleActionItem("fallback.google", "Search Google", "magnifyingglass", .blue, section: section) { WebSearch.openGoogle(query) },
            open(.files, "fallback.files", "Search Files", "doc.text.magnifyingglass", .blue),
            open(.clipboard, "fallback.clipboard", "Search Clipboard History", "clipboard", .orange),
            open(.emoji, "fallback.emoji", "Search Emoji", "face.smiling", .yellow),
        ]
    }

    private func timerItems() -> [ResultItem] {
        let timers = services.timers
        return timers.entries.map { entry in
            ResultItem(
                id: "timer.\(entry.id)", title: entry.name, icon: .symbol("timer", .orange), section: "Running Timers",
                actions: [ItemAction(title: "Cancel Timer", symbol: "stop.fill", shortcut: .enter, destructive: true, dismiss: false) { [weak navigator] in
                    timers.cancel(entry.id)
                    navigator?.refresh()
                }],
                countdown: entry.end
            )
        }
    }

    // MARK: Rows

    static func appID(_ app: AppEntry) -> String { "app:\(app.bundleID ?? app.path)" }

    private func appItem(_ app: AppEntry, section: String) -> ResultItem {
        let url = URL(fileURLWithPath: app.path)
        let id = Self.appID(app)
        var actions = [
            ItemAction(title: "Open Application", symbol: "arrow.up.forward.app", shortcut: .enter) {
                AppActivator.open(url, bundleID: app.bundleID)
            },
            ItemAction(title: "Show in Finder", symbol: "folder", shortcut: .cmdEnter) { NSWorkspace.shared.activateFileViewerSelecting([url]) },
            ItemAction(title: "Copy Path", symbol: "doc.on.doc", shortcut: .cmdShift("c")) { Paster.copy(app.path) },
        ]
        let running = app.bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        if let running {
            actions.append(ItemAction(title: "Hide Application", symbol: "eye.slash", shortcut: .cmd("h")) { running.hide() })
            actions.append(ItemAction(title: "Quit Application", symbol: "xmark.circle", shortcut: .ctrl("q")) { running.terminate() })
            actions.append(ItemAction(title: "Force Quit", symbol: "bolt.slash", destructive: true) { running.forceTerminate() })
        }
        return ResultItem(id: id, title: app.name, icon: .file(app.path), accessory: running == nil ? "Application" : "Running", section: section, actions: actions, usageKey: id)
    }

    /// Adds "Forget" to a result this query has learned, and tags it so the learning is visible.
    private func withForget(_ item: ResultItem, query: String) -> ResultItem {
        let learned = services.learned
        guard let key = item.usageKey, learned.queries.isLearned(query, id: key) else { return item }
        var item = item
        let typed = LearnedQueries.normalize(query)
        if learned.queries.preferred(query) == key { item.accessory = "“\(typed)”" }
        item.actions.append(ItemAction(title: "Forget “\(typed)” for This Result", symbol: "arrow.uturn.backward", shortcut: .ctrl("f"),
                                       dismiss: false, teachesQuery: false) { [weak navigator] in
            learned.forget(query, id: key)
            navigator?.flash("Forgot “\(typed)”", symbol: "arrow.uturn.backward")
            navigator?.refresh()
        })
        return item
    }
}
