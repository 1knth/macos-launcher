import AppKit
import ApplicationServices
import CoreServices
import Combine

struct AppEntry {
    let name: String
    let path: String
    let bundleID: String?
    let keywords: [String]
}

/// Indexes installed applications and keeps the index fresh when /Applications changes.
final class AppIndex: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []
    private var stream: FSEventStreamRef?
    private var pendingReload: DispatchWorkItem?
    private var generation = 0
    private let scanQueue = DispatchQueue(label: "app.local.prism.app-index", qos: .userInitiated)

    private var roots: [String] {
        ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
         NSHomeDirectory() + "/Applications", "/System/Library/CoreServices/Applications"]
    }

    func start() {
        guard stream == nil else { return }
        // Recursive events also catch installs in vendor folders and icon changes
        // inside an existing bundle. Watching home covers ~/Applications being created.
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                          retain: nil, release: nil, copyDescription: nil)
        let paths = (roots + [NSHomeDirectory()]).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        stream = FSEventStreamCreate(nil, { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let index = Unmanaged<AppIndex>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            guard paths.prefix(count).contains(where: { path in
                index.roots.contains { root in
                    let root = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
                    return path == root || path.hasPrefix(root + "/") || root.hasPrefix(path + "/")
                }
            }) else { return }
            index.pendingReload?.cancel()
            let work = DispatchWorkItem { [weak index] in index?.reload() }
            index.pendingReload = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            if !FSEventStreamStart(stream) {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }
        reload()
    }

    deinit {
        pendingReload?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func reload() {
        pendingReload?.cancel()
        generation += 1
        let generation = self.generation
        let roots = self.roots
        scanQueue.async {
            var seen = Set<String>()
            var found: [AppEntry] = []
            let extras = ["/System/Library/CoreServices/Finder.app"]
            let paths = roots.flatMap { root -> [String] in
                ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).flatMap { name -> [String] in
                    let path = (root as NSString).appendingPathComponent(name)
                    if name.hasSuffix(".app") { return [path] }
                    // One level of folders, e.g. /Applications/Adobe Photoshop/Photoshop.app.
                    var isDirectory: ObjCBool = false
                    guard !root.hasPrefix("/System"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
                    return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { $0.hasSuffix(".app") }.map { (path as NSString).appendingPathComponent($0) }
                }
            } + extras
            for path in paths {
                let bundle = Bundle(path: path)
                let id = bundle?.bundleIdentifier
                guard seen.insert(id ?? path).inserted else { continue }
                var name = FileManager.default.displayName(atPath: path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                var keywords: [String] = []
                if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String, bundleName != name { keywords.append(bundleName) }
                if id == "com.apple.systempreferences" { keywords += ["preferences", "settings"] }
                if id == "com.apple.ActivityMonitor" { keywords += ["task manager", "processes"] }
                found.append(AppEntry(name: name, path: path, bundleID: id, keywords: keywords))
            }
            found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                IconCache.invalidate()
                self.apps = found
            }
        }
    }
}

/// Opens apps, bringing an already-running app forward on the Space where its windows live.
enum AppActivator {
    static func open(_ url: URL, bundleID: String?) {
        if let bundleID,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated }),
           focusExistingWindow(of: running) {
            return
        }
        // Not running, or no windows to switch to: launch / reopen like clicking the Dock icon.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func focusExistingWindow(of app: NSRunningApplication) -> Bool {
        if app.isHidden { app.unhide() }
        let pid = app.processIdentifier
        if Accessibility.trusted, let (element, window) = accessibleWindow(pid: pid) {
            if isMinimized(window) { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            if !WindowServerFocus.focus(window, pid: pid) {
                AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                app.activate(options: [.activateAllWindows])
            }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return true
        }
        // Accessibility only lists windows on the current Space. The window server lists every
        // Space, so focusing one of those windows switches to the Space it lives on.
        if let windowID = WindowServerFocus.frontWindowID(pid: pid), focus(windowID: windowID, pid: pid) {
            return true
        }
        // Without Accessibility, plain activation still switches Spaces when macOS allows it.
        return Accessibility.trusted ? false : app.activate(options: [.activateAllWindows])
    }

    /// Focuses one window by ID, moving to its Space.
    @discardableResult
    static func focus(windowID: CGWindowID, pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid), app.isHidden { app.unhide() }
        guard WindowServerFocus.focus(windowID: windowID, pid: pid) else {
            return NSRunningApplication(processIdentifier: pid)?.activate(options: []) ?? false
        }
        // Focusing alone doesn't move Spaces when the "switch to a Space with open windows"
        // setting is off; raising the window's Accessibility element does.
        if Accessibility.trusted, let window = WindowServerFocus.element(forWindow: windowID, pid: pid) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        return true
    }

    private static func accessibleWindow(pid: pid_t) -> (AXUIElement, AXUIElement)? {
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], !windows.isEmpty else { return nil }
        return (element, windows.first { !isMinimized($0) } ?? windows[0])
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        return (value as? Bool) ?? false
    }
}

/// Focuses a specific window through the window server, the way AltTab does. Unlike plain
/// activation this moves to the window's Space even when "When switching to an application,
/// switch to a Space with open windows" is off. Uses private symbols looked up at runtime, so
/// a future macOS that drops them falls back to normal activation instead of crashing.
enum WindowServerFocus {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias CreateWithToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias GetPSN = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFront = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEvent = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    static func focus(_ window: AXUIElement, pid: pid_t) -> Bool {
        guard let getWindow = symbol("_AXUIElementGetWindow", in: nil, as: GetWindow.self) else { return false }
        var windowID: CGWindowID = 0
        guard getWindow(window, &windowID) == .success, windowID != 0 else { return false }
        return focus(windowID: windowID, pid: pid)
    }

    /// The app's frontmost normal window across all Spaces. Needs no permissions: only IDs,
    /// layers and bounds are read, not titles.
    static func frontWindowID(pid: pid_t) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 50, bounds.height > 50,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            return id
        }
        return nil
    }

    /// Finds the Accessibility element of a window on another Space, which kAXWindowsAttribute
    /// omits, by probing remote element tokens the way AltTab does.
    static func element(forWindow windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
        guard let create = symbol("_AXUIElementCreateWithRemoteToken", in: nil, as: CreateWithToken.self),
              let getWindow = symbol("_AXUIElementGetWindow", in: nil, as: GetWindow.self) else { return nil }
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: UInt32(0x636F_636F)) { Data($0) })
        let deadline = Date().addingTimeInterval(0.1)
        for elementID in UInt64(0)..<2000 where Date() < deadline {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
            var id: CGWindowID = 0
            if getWindow(element, &id) == .success, id == windowID { return element }
        }
        return nil
    }

    static func focus(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let getPSN = symbol("GetProcessForPID", in: nil, as: GetPSN.self),
              let setFront = symbol("_SLPSSetFrontProcessWithOptions", in: skyLight, as: SetFront.self),
              let post = symbol("SLPSPostEventRecordTo", in: skyLight, as: PostEvent.self) else { return false }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        guard setFront(&psn, windowID, userGenerated) == .success else { return false }
        // Synthesized "make key window" event records, as used by AltTab.
        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        withUnsafeBytes(of: windowID) { raw in for (offset, byte) in raw.enumerated() { bytes[0x3C + offset] = byte } }
        for index in 0x20..<0x30 { bytes[index] = 0xFF }
        bytes[0x08] = 0x01
        _ = post(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = post(&psn, &bytes)
        return true
    }
}
