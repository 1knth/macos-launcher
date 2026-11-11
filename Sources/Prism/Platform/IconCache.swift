import AppKit

enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func invalidate() { cache.removeAllObjects() }

    static func icon(_ path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 64, height: 64)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
