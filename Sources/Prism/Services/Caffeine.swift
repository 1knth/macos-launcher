import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake, like `caffeinate -d`.
final class Caffeine {
    private var assertion: IOPMAssertionID = 0
    private(set) var active = false
    var onChange: (() -> Void)?

    func toggle() {
        if active {
            IOPMAssertionRelease(assertion)
            active = false
            Toast.show("Mac can sleep again", symbol: "moon.zzz.fill", tint: .systemIndigo)
        } else {
            active = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Prism Keep Awake" as CFString, &assertion) == kIOReturnSuccess
            if active { Toast.show("Keeping your Mac awake", symbol: "cup.and.saucer.fill", tint: .systemBrown) }
        }
        onChange?()
    }
}
