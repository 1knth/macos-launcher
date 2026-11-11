import AppKit

/// System actions with no public API: locking the screen, toggling Finder's hidden files.
enum SystemActions {
    static func lockScreen() {
        // SACLockScreenImmediate is what the  menu's Lock Screen item calls.
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            typealias Lock = @convention(c) () -> Int32
            _ = unsafeBitCast(symbol, to: Lock.self)()
            return
        }
        Shell.run("/usr/bin/pmset", ["displaysleepnow"])
    }

    static func toggleHiddenFiles() {
        let current = UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "AppleShowAllFiles") ?? false
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", current ? "false" : "true"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Shell.run("/usr/bin/killall", ["Finder"]) }
    }
}
