import AppKit
import Carbon
import SwiftUI

/// User-editable shortcuts: global hotkeys (each with a primary and an optional secondary binding)
/// and the window drag gestures. Changes are saved immediately and re-registered.
final class PrismSettings: ObservableObject {
    static let shared = PrismSettings()
    struct Shortcut: Identifiable {
        var id: String { name }
        let name: String
        let binding: HotKeys.Binding
        let active: Bool
        var secondary: HotKeys.Binding?
        var secondaryActive = true
    }
    /// Which binding of which shortcut is being recorded.
    struct Slot: Equatable {
        let name: String
        let secondary: Bool
    }
    @Published var shortcuts: [Shortcut] = []
    @Published var recording: Slot?
    @Published var feedback = ""
    @Published private(set) var dragBindings = DragBindings.load()
    var reloadShortcuts: (() -> Void)?
    var menuChanged: (() -> Void)?
    private var monitor: Any?

    // MARK: Global shortcuts

    /// The user's binding for a shortcut's slot; nil means the default (primary) or none (secondary).
    func saved(_ name: String, secondary: Bool = false) -> HotKeys.Binding? {
        Self.load(secondary)[name]
    }

    private func save(_ binding: HotKeys.Binding?, for slot: Slot) {
        var values = Self.load(slot.secondary)
        values[slot.name] = binding
        if let encoded = try? JSONEncoder().encode(values) { UserDefaults.standard.set(encoded, forKey: Self.key(slot.secondary)) }
    }

    private static func key(_ secondary: Bool) -> String { secondary ? DefaultsKey.secondaryShortcuts : DefaultsKey.customShortcuts }

    private static func load(_ secondary: Bool) -> [String: HotKeys.Binding] {
        guard let data = UserDefaults.standard.data(forKey: key(secondary)),
              let values = try? JSONDecoder().decode([String: HotKeys.Binding].self, from: data) else { return [:] }
        return values
    }

    func record(_ name: String, secondary: Bool = false) {
        cancelRecording()
        let slot = Slot(name: name, secondary: secondary)
        feedback = "Press a shortcut with ⌘, ⌥ or ⌃. Esc cancels."
        recording = slot
        // Let existing Prism shortcuts be captured without triggering their actions.
        HotKeys.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == KeyCode.escape { self.cancelRecording(); return nil }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                self.feedback = "Include Command, Option or Control in the shortcut."
                return nil
            }
            if flags == .command, [43, 12, 13].contains(event.keyCode) {
                self.feedback = "That shortcut is reserved for Settings, Quit or Close."
                return nil
            }
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            let special: [UInt16: String] = [49: "Space", 36: "↩", 48: "Tab", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑"]
            let label = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            let binding = HotKeys.Binding(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label)
            if let owner = self.owner(of: binding, except: slot) {
                self.feedback = "Already assigned to \(owner). Choose another shortcut."
                return nil
            }
            let previous = self.saved(name, secondary: secondary)
            self.endRecording()
            self.save(binding, for: slot)
            self.reloadShortcuts?()
            let shortcut = self.shortcuts.first { $0.name == name }
            if (secondary ? shortcut?.secondaryActive : shortcut?.active) != true {
                self.save(previous, for: slot)
                self.reloadShortcuts?()
                self.feedback = "Shortcut unavailable. Your previous shortcut was restored."
            } else {
                self.feedback = "\(name) is now \(binding.display)\(secondary ? " (secondary)" : "")."
            }
            self.menuChanged?()
            return nil
        }
    }

    /// The shortcut already using these keys in any slot other than `slot`.
    private func owner(of binding: HotKeys.Binding, except slot: Slot) -> String? {
        func same(_ other: HotKeys.Binding?) -> Bool { other?.keyCode == binding.keyCode && other?.modifiers == binding.modifiers }
        for shortcut in shortcuts {
            if same(shortcut.binding), slot != Slot(name: shortcut.name, secondary: false) { return shortcut.name }
            if same(shortcut.secondary), slot != Slot(name: shortcut.name, secondary: true) { return shortcut.name }
        }
        return nil
    }

    private func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }

    func cancelRecording() {
        guard recording != nil else { return }
        endRecording()
        reloadShortcuts?()
        feedback = "Shortcut change canceled."
    }

    func clearSecondary(_ name: String) {
        cancelRecording()
        save(nil, for: Slot(name: name, secondary: true))
        reloadShortcuts?()
        menuChanged?()
        feedback = "Removed the secondary shortcut for \(name)."
    }

    /// Back to the default: the original primary keys and no secondary.
    func reset(_ name: String) {
        cancelRecording()
        save(nil, for: Slot(name: name, secondary: false))
        save(nil, for: Slot(name: name, secondary: true))
        reloadShortcuts?()
        menuChanged?()
        feedback = "Default shortcut restored for \(name)."
    }

    // MARK: Window drag gestures

    /// Sets one slot of a drag gesture; nil clears a secondary. Refuses a gesture another slot already uses.
    func setDrag(_ binding: DragBinding?, for action: DragAction, secondary: Bool) {
        if let binding {
            for (other, slots) in dragBindings {
                if slots.primary == binding, (other, false) != (action, secondary) { feedback = "\(binding.display) already does \(other.title)."; return }
                if slots.secondary == binding, (other, true) != (action, secondary) { feedback = "\(binding.display) already does \(other.title)."; return }
            }
        }
        var slots = dragBindings[action] ?? DragSlots()
        if secondary { slots.secondary = binding } else { slots.primary = binding }
        dragBindings[action] = slots
        applyDragBindings()
        feedback = binding.map { "\(action.title) is now \($0.display)\(secondary ? " (secondary)" : "")." } ?? "Removed the secondary gesture for \(action.title)."
    }

    func resetDrag(_ action: DragAction) {
        dragBindings[action] = DragBindings.defaults[action]
        applyDragBindings()
        feedback = "Default gestures restored for \(action.title)."
    }

    private func applyDragBindings() {
        DragBindings.save(dragBindings)
        AppServices.shared.windowDragger.reload()
    }
}

final class SettingsController: NSObject, NSWindowDelegate {
    static let shared = SettingsController()
    private var window: NSWindow?

    func show() {
        AppServices.shared.launcher?.hide()
        if window == nil {
            let controller = NSHostingController(rootView: PrismSettingsView())
            // Bridge the sidebar's navigation title and toolbar into the window, like System Settings.
            controller.sceneBridgingOptions = [.title, .toolbars]
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.title = "Prism Settings"
            window.isReleasedWhenClosed = false
            window.setContentSize(CGSize(width: 760, height: 560))
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { PrismSettings.shared.cancelRecording() }
    func windowDidResignKey(_ notification: Notification) { PrismSettings.shared.cancelRecording() }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, extensions, shortcuts, permissions
    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .extensions: "Extensions"
        case .shortcuts: "Keyboard Shortcuts"
        case .permissions: "Privacy & Security"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .extensions: "puzzlepiece.extension.fill"
        case .shortcuts: "keyboard.fill"
        case .permissions: "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .extensions: .indigo
        case .shortcuts: .gray
        case .permissions: .blue
        }
    }
}

/// System Settings–style icon: a white symbol on a tinted rounded square.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct PrismSettingsView: View {
    @State private var pane: SettingsPane? = .general
    @State private var accessibility = Accessibility.trusted
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(pane: SettingsPane = .general) { _pane = State(initialValue: pane) }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label { Text(pane.title) } icon: { SettingsIcon(symbol: pane.symbol, tint: pane.tint) }
            }
            .navigationSplitViewColumnWidth(215)
        } detail: {
            let selected = pane ?? .general
            Group {
                switch selected {
                case .general: GeneralPane()
                case .extensions: ExtensionsPane(accessibility: accessibility)
                case .shortcuts: ShortcutsPane()
                case .permissions: PermissionsPane(accessibility: accessibility, screenRecording: screenRecording)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selected.title)
        }
        .frame(minWidth: 680, minHeight: 440)
        .onReceive(refresh) { _ in
            accessibility = Accessibility.trusted
            screenRecording = CGPreflightScreenCaptureAccess()
        }
    }
}

private struct GeneralPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("View Usage…") { AppServices.shared.launcher?.show(.usage) }
                } label: {
                    Text("AI Usage Limits")
                    Text("Claude and GPT / Codex subscription usage and reset times.")
                }
            }
            Section("Command Palette") {
                LabeledContent("Settings", value: "⌘,")
                LabeledContent("All Actions", value: "⌘K")
                LabeledContent("Go Back", value: "Esc")
                LabeledContent("Close", value: "⌘W")
            }
        }
    }
}

private struct ExtensionsPane: View {
    let accessibility: Bool
    @ObservedObject private var settings = PrismSettings.shared
    @AppStorage(DefaultsKey.windowDragging) private var windowDragging = true
    @AppStorage(DefaultsKey.windowShortcuts) private var windowShortcuts = true
    @AppStorage(DefaultsKey.clipboardPaused) private var clipboardPaused = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $windowDragging) {
                    Text("Window Dragging")
                    Text("Hold modifier keys and drag anywhere on screen to move or resize the active window. By default ⌃⌘ drag moves, and ⌃⌘ right-drag or ⌃⌥ drag resizes. Change them in Keyboard Shortcuts.")
                }
                .onChange(of: windowDragging) { _, _ in AppServices.shared.windowDragger.reload() }
                Toggle(isOn: $windowShortcuts) {
                    Text("Window Shortcuts")
                    Text("⌃⌥ with arrows, ↩, C, ⌫, D, F and G for halves, maximize, center, restore and thirds.")
                }
                .onChange(of: windowShortcuts) { _, _ in
                    settings.cancelRecording()
                    settings.reloadShortcuts?()
                    settings.menuChanged?()
                }
                Toggle(isOn: Binding(get: { !clipboardPaused }, set: { clipboardPaused = !$0 })) {
                    Text("Clipboard History")
                    Text("Record text, links, images, files and colors you copy. Turning it off keeps saved items.")
                }
            } footer: {
                if !accessibility, windowDragging || windowShortcuts {
                    Text("Window extensions need Accessibility access in Privacy & Security.")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct ShortcutsPane: View {
    @ObservedObject private var settings = PrismSettings.shared

    var body: some View {
        Form {
            Section {
                ForEach(settings.shortcuts) { shortcut in
                    LabeledContent {
                        HStack(spacing: 6) {
                            keysButton(shortcut.name, binding: shortcut.binding, secondary: false)
                            secondaryButton(shortcut)
                            resetButton("Restore default shortcut", for: shortcut.name) { settings.reset(shortcut.name) }
                        }
                    } label: {
                        Text(shortcut.name)
                        if !shortcut.active { Text("Unavailable — choose another shortcut").foregroundStyle(.orange) }
                        if shortcut.secondary != nil, !shortcut.secondaryActive { Text("Secondary unavailable — choose another").foregroundStyle(.orange) }
                    }
                }
            } header: {
                Text("Click a shortcut, then press the new keys. Click None to add a secondary shortcut. Changes are saved automatically.")
                    .font(.callout).fontWeight(.regular).foregroundStyle(.secondary)
            }
            Section {
                ForEach(DragAction.allCases) { action in
                    let slots = settings.dragBindings[action] ?? DragSlots()
                    LabeledContent {
                        HStack(spacing: 6) {
                            dragPicker(action, current: slots.primary, secondary: false)
                            dragPicker(action, current: slots.secondary, secondary: true)
                            resetButton("Restore default gestures", for: action.title) { settings.resetDrag(action) }
                        }
                    } label: {
                        Text(action.title)
                    }
                }
            } header: {
                Text("Window Gestures")
            } footer: {
                VStack(alignment: .trailing, spacing: 6) {
                    if !settings.feedback.isEmpty { Text(settings.feedback).foregroundStyle(.secondary) }
                    if settings.recording != nil { Button("Cancel Recording") { settings.cancelRecording() } }
                }
            }
        }
    }

    private func keysButton(_ name: String, binding: HotKeys.Binding, secondary: Bool) -> some View {
        let recording = settings.recording == PrismSettings.Slot(name: name, secondary: secondary)
        return Button(recording ? "Press keys…" : binding.display) { settings.record(name, secondary: secondary) }
            .monospaced().frame(minWidth: 96)
            .accessibilityLabel("Change \(secondary ? "secondary " : "")shortcut for \(name)")
            .accessibilityValue(binding.display)
    }

    @ViewBuilder private func secondaryButton(_ shortcut: PrismSettings.Shortcut) -> some View {
        if let secondary = shortcut.secondary {
            keysButton(shortcut.name, binding: secondary, secondary: true)
            Button { settings.clearSecondary(shortcut.name) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove secondary shortcut")
                .accessibilityLabel("Remove secondary shortcut for \(shortcut.name)")
        } else {
            let recording = settings.recording == PrismSettings.Slot(name: shortcut.name, secondary: true)
            Button(recording ? "Press keys…" : "None") { settings.record(shortcut.name, secondary: true) }
                .foregroundStyle(.secondary).frame(minWidth: 96)
                .help("Add a secondary shortcut")
                .accessibilityLabel("Add secondary shortcut for \(shortcut.name)")
        }
    }

    private func dragPicker(_ action: DragAction, current: DragBinding?, secondary: Bool) -> some View {
        Menu(current?.display ?? "None") {
            if secondary {
                Button("None") { settings.setDrag(nil, for: action, secondary: true) }
                Divider()
            }
            ForEach(DragBinding.choices, id: \.self) { choice in
                Button(choice.display) { settings.setDrag(choice, for: action, secondary: secondary) }
            }
        }
        .monospaced()
        .fixedSize()
        .frame(minWidth: 96)
        .accessibilityLabel("\(secondary ? "Secondary" : "Primary") gesture for \(action.title)")
    }

    private func resetButton(_ help: String, for name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "arrow.counterclockwise") }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel("\(help) for \(name)")
    }
}

private struct PermissionsPane: View {
    let accessibility: Bool
    let screenRecording: Bool

    var body: some View {
        Form {
            Section {
                permission("Accessibility", detail: "Paste into other apps, read selected text, and move, resize and drag their windows.",
                           symbol: "accessibility", granted: accessibility, pane: "Accessibility")
                permission("Screen Recording", detail: "Capture text from a selected area of your screen.",
                           symbol: "rectangle.dashed.badge.record", granted: screenRecording, pane: "ScreenCapture")
            } footer: {
                Text("Status updates automatically. macOS may require restarting Prism after changing access.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func permission(_ title: String, detail: String, symbol: String, granted: Bool, pane: String) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Label(granted ? "Allowed" : "Not Allowed", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    .labelStyle(.titleAndIcon)
                Button(granted ? "Manage…" : "Allow…") {
                    if pane == "Accessibility", !granted { Accessibility.ensureTrusted() }
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") { NSWorkspace.shared.open(url) }
                }
                .accessibilityLabel("\(granted ? "Manage" : "Allow") \(title) access in System Settings")
            }
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                SettingsIcon(symbol: symbol, tint: .blue)
            }
        }
    }
}
