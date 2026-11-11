import AppKit
import SwiftUI

struct ColorWheelView: View {
    @ObservedObject var wheel: ColorWheelModel

    var body: some View {
        let color = wheel.color
        let formats = ColorFormats(color: color)
        HStack(alignment: .top, spacing: 26) {
            VStack(spacing: 16) {
                HueSaturationWheel(hue: $wheel.hue, saturation: $wheel.saturation, brightness: wheel.brightness)
                    .frame(width: 214, height: 214)
                GradientSlider(value: $wheel.brightness, colors: [.black, Color(hue: wheel.hue, saturation: wheel.saturation, brightness: 1)], label: "Brightness")
                GradientSlider(value: $wheel.alpha, colors: [Color(nsColor: color).opacity(0), Color(nsColor: color).opacity(1)], label: "Opacity", checkered: true)
            }
            .frame(width: 214)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: color))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.12)))
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formats.hex).font(.system(size: 22, weight: .semibold, design: .monospaced))
                        Text(Self.contrastNote(color)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(formats.all, id: \.0) { label, value in
                        FormatRow(label: label, value: value, color: color)
                        if label != formats.all.last?.0 { Divider().opacity(0.5) }
                    }
                }
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.04)))

                Text("Harmonies").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    harmony("Complement", [0.5])
                    harmony("Analogous", [-1 / 12, 1 / 12])
                    harmony("Triadic", [1 / 3, 2 / 3])
                }
                shades
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func harmony(_ name: String, _ offsets: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(Array(([0] + offsets).enumerated()), id: \.offset) { _, offset in
                    let hue = (wheel.hue + offset).truncatingRemainder(dividingBy: 1) + ((wheel.hue + offset) < 0 ? 1 : 0)
                    Swatch(color: NSColor(hue: hue, saturation: wheel.saturation, brightness: wheel.brightness, alpha: 1)) { picked in select(picked) }
                }
            }
            Text(name).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    private var shades: some View {
        HStack(spacing: 3) {
            ForEach(0..<9, id: \.self) { step in
                let brightness = 0.15 + Double(step) * 0.105
                Swatch(color: NSColor(hue: wheel.hue, saturation: wheel.saturation, brightness: brightness, alpha: 1), size: 22) { picked in select(picked) }
            }
        }
    }

    private func select(_ color: NSColor) { wheel.setHSB(of: color) }

    /// WCAG contrast against white and black, handy when choosing text colors.
    static func contrastNote(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "" }
        func channel(_ value: CGFloat) -> CGFloat { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
        let white = 1.05 / (luminance + 0.05), black = (luminance + 0.05) / 0.05
        return String(format: "Contrast: %.1f:1 on white · %.1f:1 on black", white, black)
    }
}

private struct FormatRow: View {
    let label: String
    let value: String
    let color: NSColor
    @State private var hovering = false

    var body: some View {
        Button {
            Paster.copy(value)
            Toast.show("Copied \(value)", swatch: color)
        } label: {
            HStack {
                Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                Text(value).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                Spacer()
                Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundStyle(.secondary).opacity(hovering ? 1 : 0.35)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct Swatch: View {
    let color: NSColor
    var size: CGFloat = 26
    let onPick: (NSColor) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: color))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.1)))
            .frame(width: size, height: size)
            .help(color.hexString)
            .onTapGesture { onPick(color) }
    }
}

struct HueSaturationWheel: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    let brightness: Double

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                // SwiftUI's angular gradient runs clockwise from 3 o'clock, matching the drag math below.
                Circle().fill(AngularGradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle().fill(Color.black.opacity(1 - brightness))
                Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .position(x: center.x + cos(hue * 2 * .pi) * saturation * radius, y: center.y + sin(hue * 2 * .pi) * saturation * radius)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let dx = drag.location.x - center.x, dy = drag.location.y - center.y
                var angle = atan2(dy, dx) / (2 * .pi)
                if angle < 0 { angle += 1 }
                hue = angle
                saturation = min(1, sqrt(dx * dx + dy * dy) / radius)
            })
        }
    }
}

struct GradientSlider: View {
    @Binding var value: Double
    let colors: [Color]
    let label: String
    var checkered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(round(value * 100)))%").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    if checkered { Checkerboard().clipShape(Capsule()) }
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                    Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: value * (geometry.size.width - 16))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    value = min(1, max(0, (drag.location.x - 8) / (geometry.size.width - 16)))
                })
            }
            .frame(height: 16)
        }
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 4
            for row in 0..<Int(ceil(size.height / cell)) {
                for column in 0..<Int(ceil(size.width / cell)) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(.gray.opacity(0.35)))
                }
            }
        }
    }
}
