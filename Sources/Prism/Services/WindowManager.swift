import AppKit
import ApplicationServices

enum WindowAction: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, almostMaximize, center
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeft, topRight, bottomLeft, bottomRight, nextDisplay, restore

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .center: return "Center"
        case .leftThird: return "First Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Last Third"
        case .leftTwoThirds: return "First Two Thirds"
        case .rightTwoThirds: return "Last Two Thirds"
        case .topLeft: return "Top Left Quarter"
        case .topRight: return "Top Right Quarter"
        case .bottomLeft: return "Bottom Left Quarter"
        case .bottomRight: return "Bottom Right Quarter"
        case .nextDisplay: return "Next Display"
        case .restore: return "Restore"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .maximize: return "rectangle.fill"
        case .almostMaximize: return "rectangle.inset.filled"
        case .center: return "rectangle.center.inset.filled"
        case .leftThird, .leftTwoThirds: return "rectangle.leadingthird.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .rightThird, .rightTwoThirds: return "rectangle.trailingthird.inset.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .nextDisplay: return "display.2"
        case .restore: return "arrow.uturn.backward"
        }
    }
}

/// Moves the frontmost app's focused window through the Accessibility API.
enum WindowManager {
    private static var previousFrames: [String: CGRect] = [:]

    static func perform(_ action: WindowAction) {
        guard Accessibility.ensureTrusted() else {
            Toast.show("Allow Accessibility for Prism to manage windows", symbol: "hand.raised.fill", tint: .systemOrange)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success, let value else {
            Toast.show("No window to move", symbol: "macwindow", tint: .secondaryLabelColor)
            return
        }
        let window = value as! AXUIElement
        guard let current = frame(of: window) else { return }
        let key = "\(app.processIdentifier)-\(title(of: window))"
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        // AX uses a top-left origin anchored to the primary display; AppKit uses bottom-left.
        let appKitFrame = CGRect(x: current.minX, y: primaryHeight - current.maxY, width: current.width, height: current.height)
        let screen = screens.max { $0.frame.intersection(appKitFrame).area < $1.frame.intersection(appKitFrame).area } ?? NSScreen.main!
        let area = screen.visibleFrame
        var target: CGRect

        switch action {
        case .restore:
            guard let previous = previousFrames[key] else { return }
            set(window, previous)
            previousFrames[key] = nil
            return
        case .nextDisplay:
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return }
            let next = screens[(index + 1) % screens.count].visibleFrame
            let relativeX = (appKitFrame.minX - area.minX) / area.width, relativeY = (appKitFrame.minY - area.minY) / area.height
            let width = min(appKitFrame.width, next.width), height = min(appKitFrame.height, next.height)
            target = CGRect(x: next.minX + relativeX * next.width, y: next.minY + relativeY * next.height, width: width, height: height)
            target.origin.x = min(max(target.minX, next.minX), next.maxX - width)
            target.origin.y = min(max(target.minY, next.minY), next.maxY - height)
        default:
            target = rect(for: action, in: area, current: appKitFrame)
        }
        previousFrames[key] = current
        set(window, CGRect(x: target.minX, y: primaryHeight - target.maxY, width: target.width, height: target.height))
    }

    static func rect(for action: WindowAction, in a: CGRect, current: CGRect) -> CGRect {
        let halfW = a.width / 2, halfH = a.height / 2, third = a.width / 3
        switch action {
        case .leftHalf: return CGRect(x: a.minX, y: a.minY, width: halfW, height: a.height)
        case .rightHalf: return CGRect(x: a.minX + halfW, y: a.minY, width: halfW, height: a.height)
        case .topHalf: return CGRect(x: a.minX, y: a.minY + halfH, width: a.width, height: halfH)
        case .bottomHalf: return CGRect(x: a.minX, y: a.minY, width: a.width, height: halfH)
        case .maximize: return a
        case .almostMaximize: return a.insetBy(dx: a.width * 0.05, dy: a.height * 0.05)
        case .center:
            let width = min(current.width, a.width), height = min(current.height, a.height)
            return CGRect(x: a.midX - width / 2, y: a.midY - height / 2, width: width, height: height)
        case .leftThird: return CGRect(x: a.minX, y: a.minY, width: third, height: a.height)
        case .centerThird: return CGRect(x: a.minX + third, y: a.minY, width: third, height: a.height)
        case .rightThird: return CGRect(x: a.minX + third * 2, y: a.minY, width: third, height: a.height)
        case .leftTwoThirds: return CGRect(x: a.minX, y: a.minY, width: third * 2, height: a.height)
        case .rightTwoThirds: return CGRect(x: a.minX + third, y: a.minY, width: third * 2, height: a.height)
        case .topLeft: return CGRect(x: a.minX, y: a.minY + halfH, width: halfW, height: halfH)
        case .topRight: return CGRect(x: a.minX + halfW, y: a.minY + halfH, width: halfW, height: halfH)
        case .bottomLeft: return CGRect(x: a.minX, y: a.minY, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: a.minX + halfW, y: a.minY, width: halfW, height: halfH)
        case .nextDisplay, .restore: return current
        }
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private static func title(of window: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        return value as? String ?? ""
    }

    private static func set(_ window: AXUIElement, _ frame: CGRect) {
        var position = frame.origin, size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Size, move, size again: some apps clamp size against the old screen position.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
