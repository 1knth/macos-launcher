import AppKit
import PrismCore

extension WebSearch {
    static func openGoogle(_ text: String) {
        if let url = url(google, text) { NSWorkspace.shared.open(url) }
    }
}
