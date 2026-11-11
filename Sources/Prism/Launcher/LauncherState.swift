import AppKit
import PrismCore
import SwiftUI

/// The launcher's view model: which route is showing, the query, the rows and which one is selected.
///
/// It coordinates and owns no route logic. Rows come from one `ResultProvider` per list route;
/// custom routes keep their own models (`chat`, `colorWheel`). Data flows one way:
/// query or data change → `refresh()` → provider builds rows → view renders → key or click → `perform(_:on:)`.
final class LauncherState: ObservableObject, LauncherNavigator {
    struct Flash: Equatable {
        let id = UUID()
        let text: String
        let symbol: String
    }

    @Published private(set) var route: Route = .root
    @Published var query = "" { didSet { if query != oldValue { queryChanged() } } }
    @Published private(set) var items: [ResultItem] = []
    @Published var selection = 0
    @Published var showActions = false
    @Published var actionSelection = 0
    @Published private(set) var flashMessage: Flash?
    /// Bumped to put keyboard focus back in the search field.
    @Published private(set) var focusToken = 0
    /// Row under the mouse; previews follow it while the mouse rests on a row.
    @Published private(set) var hoverID: String?

    let services: AppServices
    let chat = ChatModel()
    let colorWheel = ColorWheelModel()

    // Providers are created on first use, and each wires its own data sources to `refresh`.
    lazy var files = FileResults(navigator: self)
    lazy var transform = TransformResults()
    lazy var selected = SelectionResults(transform: transform, navigator: self)
    lazy var colors = ColorResults(services: services, navigator: self)
    private lazy var root = RootResults(services: services, commands: CommandCatalog(services: services, navigator: self), selection: selected, navigator: self)
    private lazy var clipboard = ClipboardResults(store: services.clipboard, navigator: self)
    private lazy var emoji = EmojiResults(frecency: services.frecency)
    private lazy var windows = WindowResults()
    private lazy var menuItems = MenuItemResults()
    private lazy var google = GoogleResults()

    /// Routes underneath the current one, with the query each had.
    private var stack: [(route: Route, query: String)] = []
    private var hoverWork: DispatchWorkItem?
    private var mouseAtKeyboardMove: CGPoint?
    /// Position in search history while ↑ is recalling past searches.
    private var historyIndex: Int?
    private var recalling = false

    init(services: AppServices = .shared) {
        self.services = services
    }

    private func provider(for route: Route) -> ResultProvider? {
        switch route {
        case .root: return root
        case .google: return google
        case .files: return files
        case .clipboard: return clipboard
        case .emoji: return emoji
        case .colors: return colors
        case .windows: return windows
        case .menuItems: return menuItems
        case .transform: return transform
        case .colorWheel, .chat, .usage: return nil
        }
    }

    var selectedItem: ResultItem? { items.indices.contains(selection) ? items[selection] : nil }
    var hoveredItem: ResultItem? { hoverID.flatMap { id in items.first { $0.id == id } } }
    /// The item whose actions the footer and ⌘K panel show.
    var actionItem: ResultItem? { route == .colorWheel ? colors.wheelItem(colorWheel) : selectedItem }

    // MARK: Navigation

    func push(_ next: Route, query text: String) {
        provider(for: route)?.deactivate()
        stack.append((route, query))
        showActions = false
        route = next
        provider(for: next)?.activate()
        query = text
        refresh()
        focusToken += 1
    }

    func pop() {
        guard let previous = stack.popLast() else { return }
        provider(for: route)?.deactivate()
        showActions = false
        route = previous.route
        query = previous.query
        refresh()
        focusToken += 1
    }

    /// Back to an empty root search, as every fresh open starts.
    func reset() {
        provider(for: route)?.deactivate()
        stack.removeAll()
        showActions = false
        route = .root
        query = ""
        refresh()
    }

    /// Called before the launcher appears, while the previous app still has focus.
    func captureSelection() { selected.capture() }

    func didShow() {
        focusToken += 1
        refresh(keepSelection: true)
    }

    func flash(_ text: String, symbol: String) {
        let message = Flash(text: text, symbol: symbol)
        flashMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.flashMessage == message { self?.flashMessage = nil }
        }
    }

    private func queryChanged() {
        if !recalling { historyIndex = nil }
        if route == .colorWheel { colorWheel.apply(hex: query) }
        refresh()
    }

    /// Rebuilds the rows for the current route. `keepSelection` keeps the same row selected when it's still there.
    func refresh(keepSelection: Bool) {
        let previousID = selectedItem?.id
        items = provider(for: route)?.items(for: query) ?? []
        if keepSelection, let previousID, let index = items.firstIndex(where: { $0.id == previousID }) {
            selection = index
        } else {
            selection = 0
        }
        if items.isEmpty { showActions = false }
        if hoverID != nil, hoveredItem == nil { hoverID = nil }
    }

    // MARK: Mouse

    /// In list+detail views hovering selects the row (so the preview follows the mouse);
    /// elsewhere it only drives the floating image preview.
    func hover(_ id: String, inside: Bool) {
        hoverWork?.cancel()
        // Rows scrolling under a resting mouse during keyboard navigation aren't real hovers.
        if inside, NSEvent.mouseLocation == mouseAtKeyboardMove { return }
        let work: DispatchWorkItem
        if !inside {
            work = DispatchWorkItem { [weak self] in if self?.hoverID == id { self?.hoverID = nil } }
        } else if route.hasDetail {
            work = DispatchWorkItem { [weak self] in
                guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.selection = index
            }
        } else {
            work = DispatchWorkItem { [weak self] in self?.hoverID = id }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.12 : 0.08), execute: work)
    }

    func clearHover() {
        hoverWork?.cancel()
        hoverID = nil
    }

    // MARK: Search history

    /// Remembers the root search so ↑ can bring it back next time.
    func recordSearch() {
        if route == .root { services.searchHistory.record(query) }
    }

    /// ↑ from an empty root search (or while already recalling) steps back through past searches.
    func recallOlderSearch() -> Bool {
        guard route == .root, selection == 0, query.isEmpty || historyIndex != nil else { return false }
        let entries = services.searchHistory.entries
        let next = (historyIndex ?? -1) + 1
        guard entries.indices.contains(next) else { return historyIndex != nil }
        recalling = true
        historyIndex = next
        query = entries[next]
        recalling = false
        focusToken += 1
        return true
    }

    // MARK: Running actions

    /// The single path every action takes, from Return, a shortcut, a click or the ⌘K panel.
    func perform(_ action: ItemAction, on item: ResultItem?) {
        if let key = item?.usageKey {
            services.frecency.record(key)
            recordSearch()
            // Teach the root search which result this exact query means.
            if route == .root, !action.destructive, action.teachesQuery { services.learned.record(query, id: key) }
        }
        showActions = false
        if action.dismiss { services.launcher?.hide() }
        action.run()
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        clearHover()
        mouseAtKeyboardMove = NSEvent.mouseLocation
        selection = max(0, min(items.count - 1, selection + delta))
    }

    /// Esc: close the actions panel, then go back a route, then clear the query, then hide.
    func escape() {
        if showActions { showActions = false } else if route != .root { pop() } else if !query.isEmpty { query = "" } else { services.launcher?.hide() }
    }

    func openActions() {
        guard actionItem?.actions.isEmpty == false else { return }
        actionSelection = 0
        showActions = true
    }
}
