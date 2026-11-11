import AppKit

/// The Saved Colors route, plus the actions for the color on the Color Wheel.
final class ColorResults: ResultProvider {
    private unowned let navigator: LauncherNavigator
    private let services: AppServices

    init(services: AppServices, navigator: LauncherNavigator) {
        self.services = services
        self.navigator = navigator
    }

    func items(for raw: String) -> [ResultItem] {
        let query = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let services = services
        var items: [ResultItem] = []
        if query.isEmpty {
            items.append(ResultItem(id: "colors.pick", title: "Pick Color from Screen", icon: .symbol("eyedropper", .pink), section: "Tools",
                                    actions: [ItemAction(title: "Pick Color", symbol: "eyedropper", shortcut: .enter, dismiss: false) { services.pickColor() }]))
            items.append(ResultItem(id: "colors.wheel", title: "Open Color Wheel", icon: .symbol("paintpalette", .purple), section: "Tools",
                                    actions: [ItemAction(title: "Open Color Wheel", symbol: "paintpalette", shortcut: .enter, dismiss: false) { [weak navigator] in
                                        navigator?.push(.colorWheel)
                                    }]))
        }
        let needle = query.replacingOccurrences(of: "#", with: "")
        for hex in services.colors.hexes where query.isEmpty || hex.lowercased().contains(needle) {
            guard let color = NSColor(hex: hex) else { continue }
            let formats = ColorFormats(color: color)
            items.append(ResultItem(
                id: "color:\(hex)", title: hex, subtitle: formats.rgbString, icon: .color(color), section: "Saved",
                actions: Self.copyActions { formats } + [
                    ItemAction(title: "Open in Color Wheel", symbol: "paintpalette", shortcut: .cmd("o"), dismiss: false) { [weak navigator] in
                        navigator?.push(.colorWheel, query: hex)
                    },
                    ItemAction(title: "Delete Color", symbol: "trash", shortcut: .ctrl("x"), destructive: true, dismiss: false) { [weak navigator] in
                        services.colors.remove(hex)
                        navigator?.refresh()
                    },
                ]
            ))
        }
        return items
    }

    /// The footer and ⌘K actions while the Color Wheel is open. Actions read the wheel when they run,
    /// so they're never stale after the color changes.
    func wheelItem(_ wheel: ColorWheelModel) -> ResultItem {
        let services = services
        return ResultItem(
            id: "wheel", title: ColorFormats(color: wheel.color).hex, icon: .color(wheel.color), section: "",
            actions: Self.copyActions { ColorFormats(color: wheel.color) } + [
                ItemAction(title: "Save Color", symbol: "square.and.arrow.down", shortcut: .cmd("s"), dismiss: false) { [weak navigator] in
                    let hex = ColorFormats(color: wheel.color).hex
                    services.colors.add(hex)
                    navigator?.flash("Saved \(hex)", symbol: "swatchpalette")
                },
                ItemAction(title: "Pick from Screen", symbol: "eyedropper", shortcut: .cmd("p"), dismiss: false) { [weak navigator] in
                    services.pickColor { picked in
                        services.launcher?.show(resume: true)
                        navigator?.query = picked.hexString
                    }
                },
            ]
        )
    }

    private static func copyActions(_ formats: @escaping () -> ColorFormats) -> [ItemAction] {
        func copy(_ value: (ColorFormats) -> String) {
            let current = formats()
            let text = value(current)
            Paster.copy(text)
            Toast.show("Copied \(text)", swatch: current.color)
        }
        return [
            ItemAction(title: "Copy HEX", symbol: "number", shortcut: .enter) { copy(\.hex) },
            ItemAction(title: "Copy RGB", symbol: "r.square", shortcut: .cmdShift("r")) { copy(\.rgbString) },
            ItemAction(title: "Copy HSL", symbol: "h.square", shortcut: .cmdShift("h")) { copy(\.hsl) },
            ItemAction(title: "Copy HSB", symbol: "b.square", shortcut: .cmdShift("b")) { copy(\.hsb) },
        ]
    }
}
