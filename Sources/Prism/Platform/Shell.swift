import AppKit

enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        do { try process.run(); return true } catch { return false }
    }

    static func appleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                let message = error[NSAppleScript.errorMessage] as? String ?? "Script failed"
                DispatchQueue.main.async { Toast.show(message, symbol: "exclamationmark.triangle.fill") }
            }
        }
    }
}
