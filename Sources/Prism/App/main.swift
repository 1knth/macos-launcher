import AppKit

let application = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    application.setActivationPolicy(.prohibited)
    Snapshot.run(Array(CommandLine.arguments[(index + 1)...]))
}
let delegate = AppDelegate()
application.delegate = delegate
withExtendedLifetime(delegate) { application.run() }
