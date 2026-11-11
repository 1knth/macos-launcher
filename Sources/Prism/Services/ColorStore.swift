import AppKit
import SwiftUI

/// Colors picked from the screen or saved from the color wheel.
final class ColorStore {
    private let key = DefaultsKey.savedColors
    private(set) var hexes: [String]

    init() { hexes = UserDefaults.standard.stringArray(forKey: key) ?? [] }

    func add(_ hex: String) {
        hexes.removeAll { $0 == hex }
        hexes.insert(hex, at: 0)
        if hexes.count > 60 { hexes.removeLast(hexes.count - 60) }
        UserDefaults.standard.set(hexes, forKey: key)
    }

    func remove(_ hex: String) {
        hexes.removeAll { $0 == hex }
        UserDefaults.standard.set(hexes, forKey: key)
    }

    /// Opens the system loupe after a beat, so whatever the caller hid has left the screen.
    /// Use `AppServices.pickColor`, which hides the launcher first.
    func pickFromScreen(completion: ((NSColor) -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSColorSampler().show { [weak self] color in
                guard let self, let color = color?.usingColorSpace(.sRGB) else { return }
                let hex = color.hexString
                self.add(hex)
                Paster.copy(hex)
                Toast.show("Copied \(hex)", swatch: color)
                completion?(color)
            }
        }
    }
}

/// Every text representation offered by the color tools.
struct ColorFormats {
    let color: NSColor

    private var rgb: (r: Int, g: Int, b: Int, a: CGFloat) {
        let c = color.usingColorSpace(.sRGB) ?? color
        return (Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)), c.alphaComponent)
    }

    var hex: String { color.hexString }
    var rgbString: String {
        let v = rgb
        return v.a < 1 ? "rgba(\(v.r), \(v.g), \(v.b), \(String(format: "%.2f", v.a)))" : "rgb(\(v.r), \(v.g), \(v.b))"
    }

    var hsl: String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let h = c.hueComponent, s = c.saturationComponent, b = c.brightnessComponent
        let l = b * (1 - s / 2)
        let sl = (l == 0 || l == 1) ? 0 : (b - l) / min(l, 1 - l)
        return "hsl(\(Int(round(h * 360))), \(Int(round(sl * 100)))%, \(Int(round(l * 100)))%)"
    }

    var hsb: String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return "hsb(\(Int(round(c.hueComponent * 360))), \(Int(round(c.saturationComponent * 100)))%, \(Int(round(c.brightnessComponent * 100)))%)"
    }

    var all: [(String, String)] { [("HEX", hex), ("RGB", rgbString), ("HSL", hsl), ("HSB", hsb)] }
}
