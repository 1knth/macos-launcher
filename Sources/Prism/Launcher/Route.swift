import SwiftUI

/// A screen in the launcher. Routes stack: Esc pops back to the one underneath.
enum Route: Equatable {
    case root, files, clipboard, emoji, colorWheel, colors, windows, menuItems, transform, chat, usage, google

    /// How the content area draws the route.
    enum Layout {
        /// Rows from the route's `ResultProvider`.
        case list
        /// Rows on the left, a preview of the selected row on the right.
        case listWithDetail
        /// A custom view; the route has no rows to navigate.
        case custom
    }

    var layout: Layout {
        switch self {
        case .files, .clipboard: return .listWithDetail
        case .colorWheel, .chat, .usage: return .custom
        default: return .list
        }
    }

    var hasDetail: Bool { layout == .listWithDetail }
    /// Whether ↑↓ move through rows.
    var hasRows: Bool { layout != .custom }
    /// Chat edits its draft in its own composer and usage has nothing to search, so both show a title instead.
    var hasSearchField: Bool { self != .chat && self != .usage }

    var title: String {
        switch self {
        case .google: return "Google"
        case .usage: return "AI Usage Limits"
        case .chat: return "Ask AI"
        case .root: return "Search"
        case .files: return "Search Files"
        case .clipboard: return "Clipboard History"
        case .emoji: return "Emoji"
        case .colorWheel: return "Color Wheel"
        case .colors: return "Saved Colors"
        case .windows: return "Switch Windows"
        case .menuItems: return "Menu Items"
        case .transform: return "Transform Text"
        }
    }

    var placeholder: String {
        switch self {
        case .google: return "Search Google…"
        case .usage: return "AI Usage Limits"
        case .chat: return "Ask Luna a question…"
        case .root: return "Search apps, commands, files, calculate, or ask AI…"
        case .files: return "Search files…  (kind:image, ext:pdf)"
        case .clipboard: return "Search clipboard history…"
        case .emoji: return "Search emoji…"
        case .colorWheel: return "Type a hex color, e.g. #5E5CE6"
        case .colors: return "Search saved colors…"
        case .windows: return "Search open windows…"
        case .menuItems: return "Search menu items…"
        case .transform: return "Search transforms…"
        }
    }

    var icon: ItemIcon {
        switch self {
        case .google: return .symbol("magnifyingglass", .blue)
        case .usage: return .symbol("chart.bar", .orange)
        case .chat: return .symbol("sparkles", .indigo)
        case .root: return .symbol("sparkle.magnifyingglass", .indigo)
        case .files: return .symbol("doc.text.magnifyingglass", .blue)
        case .clipboard: return .symbol("clipboard", .orange)
        case .emoji: return .symbol("face.smiling", .yellow)
        case .colorWheel: return .symbol("paintpalette", .pink)
        case .colors: return .symbol("swatchpalette", .purple)
        case .windows: return .symbol("macwindow.on.rectangle", .cyan)
        case .menuItems: return .symbol("filemenu.and.selection", .gray)
        case .transform: return .symbol("textformat", .green)
        }
    }
}
