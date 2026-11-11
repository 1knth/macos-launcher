import AppKit
import SwiftUI

/// One row in the launcher. Rows are plain values rebuilt on every refresh; everything a row
/// can do lives in its `actions`, the first of which runs on Return.
struct ResultItem: Identifiable {
    let id: String
    var title: String
    var subtitle: String?
    var icon: ItemIcon
    var accessory: String?
    /// Consecutive rows with the same section are grouped under one header.
    var section: String
    var actions: [ItemAction]
    var preview: ItemPreview = .none
    var style: RowStyle = .normal
    var countdown: Date?
    /// Frecency is recorded under this key when the item runs; nil skips recording.
    var usageKey: String?

    init(id: String, title: String, subtitle: String? = nil, icon: ItemIcon, accessory: String? = nil,
         section: String, actions: [ItemAction], preview: ItemPreview = .none, style: RowStyle = .normal,
         countdown: Date? = nil, usageKey: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accessory = accessory
        self.section = section
        self.actions = actions
        self.preview = preview
        self.style = style
        self.countdown = countdown
        self.usageKey = usageKey
    }
}

struct ItemAction: Identifiable {
    let id = UUID()
    var title: String
    var symbol: String
    var shortcut: KeyCombo?
    var destructive = false
    /// Hide the launcher before running. Off for actions that keep the user in Prism.
    var dismiss = true
    /// Running it teaches the root search that the typed query means this item.
    /// Off for actions about the learning itself, like "Forget".
    var teachesQuery = true
    var run: () -> Void
}

enum ItemIcon {
    case image(NSImage)
    /// A file whose Finder icon is loaded lazily through `IconCache`.
    case file(String)
    /// An SF Symbol drawn white on a tinted rounded tile, like Raycast's command icons.
    case symbol(String, Color)
    case emoji(String)
    case color(NSColor)
}

enum ItemPreview {
    case none
    case file(URL)
    case clip(ClipItem)
}

enum RowStyle {
    case normal
    case calculator(expression: String, result: String, detail: String)
}
