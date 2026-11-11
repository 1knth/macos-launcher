import AppKit
import Carbon
import SwiftUI

final class PrismSettings: ObservableObject {
    static let shared = PrismSettings()
    struct Shortcut: Identifiable {
        var id: String { name }
        let name: String
        let binding: HotKeys.Binding
        let active: Bool
    }
    @Published var shortcuts: [Shortcut] = []
    @Published var recording: String?
    @Published var feedback = ""
    var reloadShortcuts: (() -> Void)?
    var menuChanged: (() -> Void)?
    private var monitor: Any?
    private let storageKey = DefaultsKey.customShortcuts

    func saved(_ name: String) -> HotKeys.Binding? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([String: HotKeys.Binding].self, from: data) else { return nil }
        return values[name]
    }

    private func save(_ binding: HotKeys.Binding?, for name: String) {
        let data = UserDefaults.standard.data(forKey: storageKey) ?? Data()
        var values = (try? JSONDecoder().decode([String: HotKeys.Binding].self, from: data)) ?? [:]
        values[name] = binding
        if let encoded = try? JSONEncoder().encode(values) { UserDefaults.standard.set(encoded, forKey: storageKey) }
    }

    func record(_ name: String) {
        cancelRecording()
        feedback = "Press a shortcut with ⌘, ⌥ or ⌃. Esc cancels."
        recording = name
        // Let existing Prism shortcuts be captured without triggering their actions.
        HotKeys.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.cancelRecording(); return nil }
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
            if let duplicate = self.shortcuts.first(where: { $0.name != name && $0.binding.keyCode == binding.keyCode && $0.binding.modifiers == binding.modifiers }) {
                self.feedback = "Already assigned to \(duplicate.name). Choose another shortcut."
                return nil
            }
            let previous = self.saved(name)
            self.endRecording()
            self.save(binding, for: name)
            self.reloadShortcuts?()
            if self.shortcuts.first(where: { $0.name == name })?.active != true {
                self.save(previous, for: name)
                self.reloadShortcuts?()
                self.feedback = "Shortcut unavailable. Your previous shortcut was restored."
            } else {
                self.feedback = "\(name) is now \(binding.display)."
            }
            self.menuChanged?()
            return nil
        }
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

    func reset(_ name: String) {
        cancelRecording()
        save(nil, for: name)
        reloadShortcuts?()
        menuChanged?()
        feedback = "Default shortcut restored for \(name)."
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
                    Text("Hold ⌃⌘ and drag anywhere on screen to move the active window. Hold ⌃⌘ and right-drag to resize it from its center.")
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
                            Button(settings.recording == shortcut.name ? "Press keys…" : shortcut.binding.display) { settings.record(shortcut.name) }
                                .monospaced().frame(minWidth: 96)
                                .accessibilityLabel("Change shortcut for \(shortcut.name)")
                                .accessibilityValue(shortcut.binding.display)
                            Button { settings.reset(shortcut.name) } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.borderless)
                                .help("Restore default shortcut")
                                .accessibilityLabel("Restore default shortcut for \(shortcut.name)")
                        }
                    } label: {
                        Text(shortcut.name)
                        if !shortcut.active { Text("Unavailable — choose another shortcut").foregroundStyle(.orange) }
                    }
                }
            } header: {
                Text("Click a shortcut, then press the new keys. Changes are saved automatically.")
                    .font(.callout).fontWeight(.regular).foregroundStyle(.secondary)
            } footer: {
                VStack(alignment: .trailing, spacing: 6) {
                    if !settings.feedback.isEmpty { Text(settings.feedback).foregroundStyle(.secondary) }
                    if settings.recording != nil { Button("Cancel Recording") { settings.cancelRecording() } }
                }
            }
        }
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
