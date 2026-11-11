import SwiftUI

/// Builds the rows for one route. Each list route has exactly one provider, which owns whatever
/// state that route needs (a Spotlight query, a snapshot of open windows) and nothing else.
///
/// Providers are pure row factories: they read services, return `ResultItem`s, and do work only
/// inside item actions. They reach the launcher through `LauncherNavigator`, never the view.
protocol ResultProvider: AnyObject {
    /// The route was pushed. Capture system state here, once, so typing doesn't re-query it.
    func activate()
    /// The route was covered by another or popped. Stop live queries.
    func deactivate()
    func items(for query: String) -> [ResultItem]
}

extension ResultProvider {
    func activate() {}
    func deactivate() {}
}

/// What providers and their item actions may ask of the launcher.
protocol LauncherNavigator: AnyObject {
    var route: Route { get }
    var query: String { get set }
    func push(_ route: Route, query: String)
    func flash(_ text: String, symbol: String)
    func refresh(keepSelection: Bool)
}

extension LauncherNavigator {
    func push(_ route: Route) { push(route, query: "") }
    func refresh() { refresh(keepSelection: false) }
}

/// Shorthand for the common one-action row that runs on Return.
func singleActionItem(_ id: String, _ title: String, _ symbol: String, _ color: Color, section: String,
                      dismiss: Bool = true, run: @escaping () -> Void) -> ResultItem {
    ResultItem(id: id, title: title, icon: .symbol(symbol, color), section: section,
               actions: [ItemAction(title: title, symbol: "return", shortcut: .enter, dismiss: dismiss, run: run)])
}
