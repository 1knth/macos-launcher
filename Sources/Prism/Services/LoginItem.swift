import Foundation
import ServiceManagement

enum LoginItem {
    /// Cached: reading the status is a round trip to the login items service, and the command list
    /// is rebuilt on every keystroke. `reload()` picks up changes made in System Settings.
    private(set) static var enabled = SMAppService.mainApp.status == .enabled

    static func reload() {
        DispatchQueue.global(qos: .utility).async {
            let value = SMAppService.mainApp.status == .enabled
            DispatchQueue.main.async { enabled = value }
        }
    }

    static func toggle() {
        defer { enabled = SMAppService.mainApp.status == .enabled }
        do {
            if enabled {
                try SMAppService.mainApp.unregister()
                Toast.show("Prism won’t open at login", symbol: "power", tint: .secondaryLabelColor)
            } else {
                try SMAppService.mainApp.register()
                Toast.show("Prism will open at login", symbol: "power", tint: .systemGreen)
            }
        } catch {
            Toast.show("Login item: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill", tint: .systemOrange)
        }
    }
}
