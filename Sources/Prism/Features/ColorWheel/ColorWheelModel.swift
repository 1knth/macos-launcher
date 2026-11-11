import AppKit

/// The color being edited in the Color Wheel route, kept in HSB so the wheel and sliders map directly.
final class ColorWheelModel: ObservableObject {
    @Published var hue: Double = 0.66
    @Published var saturation: Double = 0.62
    @Published var brightness: Double = 0.9
    @Published var alpha: Double = 1

    var color: NSColor {
        NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: alpha).usingColorSpace(.sRGB)
            ?? NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }

    /// Adopts a typed hex color ("#5E5CE6"); anything else is ignored.
    func apply(hex: String) {
        guard let color = NSColor(hex: hex)?.usingColorSpace(.sRGB) else { return }
        setHSB(of: color)
        alpha = color.alphaComponent
    }

    /// Adopts a swatch's hue, saturation and brightness, keeping the current opacity.
    func setHSB(of color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        hue = rgb.hueComponent
        saturation = rgb.saturationComponent
        brightness = rgb.brightnessComponent
    }
}
