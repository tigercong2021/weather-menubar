import AppKit

/// Renders weather glyphs. The caller owns the animation clock.
@MainActor
final class WeatherIconRenderer {
    static let menuFramesPerSecond = 15.0
    static let menuFrameCount = Int(menuFramesPerSecond * 6)
    static let frameCount = 36
    private static let designSide: CGFloat = 18
    private static let cacheLimit = 12

    private enum Kind: Hashable {
        case neutral, clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, thunder, cycloneDemo

        init(code: Int?) {
            switch code {
            case 0: self = .clear
            case 1, 2: self = .partlyCloudy
            case 3: self = .cloudy
            case 45, 48: self = .fog
            case 51, 53, 55, 56, 57: self = .drizzle
            case 61, 63, 65, 66, 67, 80, 81, 82: self = .rain
            case 71, 73, 75, 77, 85, 86: self = .snow
            case 95, 96, 97, 99: self = .thunder
            default: self = .neutral
            }
        }
    }

    private struct Key: Hashable {
        let kind: Kind
        let day: Bool
        let dark: Bool
        let density: Int
        let side: Int
        let windy: Bool
        let template: Bool
    }

    private var frames: [Key: [NSImage]] = [:]
    private var recency: [Key] = []

    func image(code: Int?, isDay: Bool?, intensity: Double, phase: Int, dark: Bool,
               size: CGFloat = 18, gust: Double? = nil, cycloneDemo: Bool = false,
               template: Bool = false) -> NSImage {
        // The cyclone glyph is for the explicit demo. Gusts never select it.
        let kind: Kind = cycloneDemo ? .cycloneDemo : (isDay == nil ? .neutral : Kind(code: code))
        let density: Int
        switch kind {
        case .drizzle, .rain, .snow:
            density = !intensity.isFinite || intensity < 0.8 ? 0 : intensity < 4 ? 1 : 2
        default:
            density = 0
        }
        let side = (1...256).contains(size) ? Int(size.rounded()) : Int(Self.designSide)
        let windy: Bool
        switch kind {
        case .clear, .partlyCloudy, .cloudy, .fog, .drizzle, .rain:
            windy = gust.map { $0.isFinite && $0 >= 40 } ?? false
        default:
            windy = false
        }
        let key = Key(kind: kind, day: kind == .neutral ? true : (isDay ?? true),
                      dark: !template && dark, density: density, side: side, windy: windy, template: template)
        let frameCount = side == Int(Self.designSide) ? Self.menuFrameCount : Self.frameCount
        let normalized = max(0, phase) % frameCount
        recency.removeAll { $0 == key }
        recency.append(key)
        if let cached = frames[key] { return cached[kind == .neutral ? 0 : normalized] }

        // Generate a complete loop once for each active palette/condition. Both 1× and 2×
        // representations keep the AppKit button sharp when it moves between displays.
        let rendered = (0..<(kind == .neutral ? 1 : frameCount)).map {
            makeFrame(key: key, frame: $0, frameCount: frameCount)
        }
        frames[key] = rendered
        if recency.count > Self.cacheLimit { frames.removeValue(forKey: recency.removeFirst()) }
        return rendered[kind == .neutral ? 0 : normalized]
    }

    private struct Palette {
        let template: Bool
        let outline: CGColor
        let cloud: CGColor
        let cloudTop: CGColor
        let sun: CGColor
        let sunRim: CGColor
        let moon: CGColor
        let moonRim: CGColor
        let water: CGColor
        let accent: CGColor

        init(day: Bool, dark: Bool, template: Bool) {
            self.template = template
            if template {
                let ink = Self.color(0x000000)
                outline = ink
                cloud = ink
                cloudTop = ink
                sun = ink
                sunRim = ink
                moon = ink
                moonRim = ink
                water = ink
                accent = ink
                return
            }
            outline = Self.color(day ? (dark ? 0xA9C8E0 : 0x486179) : (dark ? 0xA7BCE4 : 0x525F87))
            cloud = Self.color(day ? (dark ? 0x557C9B : 0xCCDFEF) : (dark ? 0x4C608E : 0xC2CDE8))
            cloudTop = Self.color(day ? (dark ? 0x7195B1 : 0xF1F7FA) : (dark ? 0x677DA9 : 0xE8EDF7))
            sun = Self.color(dark ? 0xFFC36B : 0xFFBB58)
            sunRim = Self.color(dark ? 0xFFD78C : 0x9D520E)
            moon = Self.color(dark ? 0xBCCAFF : 0x9EADEF)
            moonRim = Self.color(dark ? 0xD1DCFF : 0x4D5BA1)
            water = Self.color(day ? (dark ? 0x85D4FC : 0x21658E) : (dark ? 0xA3C3FF : 0x465F9E))
            accent = Self.color(dark ? 0xF4CD81 : 0x965321)
        }

        static func color(_ rgb: UInt32, alpha: CGFloat = 1) -> CGColor {
            CGColor(red: CGFloat((rgb >> 16) & 255) / 255,
                    green: CGFloat((rgb >> 8) & 255) / 255,
                    blue: CGFloat(rgb & 255) / 255, alpha: alpha)
        }
    }

    private func makeFrame(key: Key, frame: Int, frameCount: Int) -> NSImage {
        let size = NSSize(width: key.side, height: key.side)
        let image = NSImage(size: size)
        let palette = Palette(day: key.day, dark: key.dark, template: key.template)
        let theta = CGFloat(frame) / CGFloat(frameCount) * 2 * .pi
        for scale in [1, 2] {
            let pixels = key.side * scale
            guard let ctx = CGContext(data: nil, width: pixels, height: pixels,
                                      bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            let drawingScale = CGFloat(pixels) / Self.designSide
            ctx.scaleBy(x: drawingScale, y: drawingScale)
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            draw(key, in: ctx, palette: palette, angle: theta)
            if let bitmap = ctx.makeImage() {
                let representation = NSBitmapImageRep(cgImage: bitmap)
                representation.size = size
                image.addRepresentation(representation)
            }
        }
        image.isTemplate = key.template
        return image
    }

    private func draw(_ key: Key, in c: CGContext, palette p: Palette, angle t: CGFloat) {
        switch key.kind {
        case .clear, .partlyCloudy, .cloudy, .fog:
            if key.windy {
                c.saveGState()
                c.translateBy(x: 2.16, y: 4)
                c.scaleBy(x: 0.76, y: 0.76)
                drawWeather(key, in: c, palette: p, angle: t)
                c.restoreGState()
                windStreams(c, palette: p, angle: t)
                return
            }
        default:
            break
        }
        drawWeather(key, in: c, palette: p, angle: t)
    }

    private func drawWeather(_ key: Key, in c: CGContext, palette p: Palette, angle t: CGFloat) {
        switch key.kind {
        case .neutral:
            let grey = key.template ? p.outline : Palette.color(key.dark ? 0xD2D8DF : 0x647080)
            c.setStrokeColor(grey)
            c.setLineWidth(1.15)
            c.addEllipse(in: CGRect(x: 4.1, y: 4.1, width: 9.8, height: 9.8))
            c.strokePath()
            line(c, from: .init(x: 6.8, y: 9), to: .init(x: 11.2, y: 9), color: grey, width: 1.2)
        case .clear:
            if key.day {
                sun(c, x: 9, y: 9, scale: 1, palette: p, angle: t)
            } else {
                moon(c, x: 7.55, y: 8.8, scale: 1, palette: p)
                star(c, x: 13.8, y: 13.0, radius: 1.45 + 0.18 * sin(t), color: p.moonRim)
                dot(c, x: 14.5, y: 7.3, radius: 0.55, color: p.moonRim, alpha: 0.75)
            }
        case .partlyCloudy:
            if key.day {
                sun(c, x: 6.4, y: 11.5, scale: 0.65, palette: p, angle: t)
            } else {
                moon(c, x: 6.0, y: 11.1, scale: 0.75, palette: p)
                dot(c, x: 11.4, y: 14.55, radius: 0.6, color: p.moonRim, alpha: 0.82 + 0.15 * sin(t))
            }
            let drift: CGFloat = key.template ? 0.48 : 0.95
            cloud(c, x: 4.35 + drift * sin(t), y: 4.0, scale: 0.84, palette: p)
        case .cloudy:
            let drift = sin(t)
            let lift = 0.25 * cos(t)
            let rearDrift: CGFloat = key.template ? 0.65 : 1.35
            let frontDrift: CGFloat = key.template ? 0.60 : 1.40
            cloud(c, x: 5.6 - rearDrift * drift, y: 7.9 + lift, scale: 0.73, palette: p, rear: true)
            cloud(c, x: 2.2 + frontDrift * drift, y: 4.25 - lift, scale: 0.94, palette: p)
        case .fog:
            cloud(c, x: 3.5, y: 9.15, scale: 0.81, palette: p)
            for i in 0..<3 {
                let shift = 0.72 * sin(t + CGFloat(i) * 1.9)
                let y = 6.7 - CGFloat(i) * 1.95
                let start = (i == 1 ? 5.0 : 3.2) + shift
                line(c, from: .init(x: start, y: y), to: .init(x: start + (i == 1 ? 8.1 : 10.5), y: y),
                     color: p.outline, width: i == 1 ? 1.1 : 0.92, alpha: i == 1 ? 0.95 : 0.75)
            }
        case .drizzle, .rain, .snow, .thunder:
            cloud(c, x: 2.9, y: 8.75, scale: 0.9, palette: p)
            if key.kind == .thunder {
                if key.template {
                    let bolt = CGMutablePath()
                    bolt.move(to: .init(x: 10.4, y: 7.25))
                    bolt.addLines(between: [.init(x: 7.85, y: 4.1), .init(x: 10.95, y: 4.1), .init(x: 8.25, y: 1.30)])
                    c.saveGState()
                    c.setAlpha(0.92 + 0.08 * sin(t))
                    c.setStrokeColor(p.outline)
                    c.setLineWidth(1.32)
                    c.addPath(bolt)
                    c.strokePath()
                    c.restoreGState()
                    return
                }
                let bolt = CGMutablePath()
                bolt.move(to: .init(x: 9.1, y: 9.1))
                bolt.addLines(between: [.init(x: 11.7, y: 9.1), .init(x: 10.0, y: 6.0), .init(x: 12.1, y: 6.0),
                                        .init(x: 7.45, y: 1.75), .init(x: 8.45, y: 5.0), .init(x: 6.6, y: 5.0)])
                bolt.closeSubpath()
                c.saveGState()
                c.setAlpha((key.day ? 0.87 : 0.76) + 0.08 * sin(t))
                c.setFillColor(p.sun)
                c.setStrokeColor(p.accent)
                c.setLineWidth(0.9)
                c.addPath(bolt)
                c.drawPath(using: .fillStroke)
                c.restoreGState()
            } else if key.template {
                templatePrecipitation(c, kind: key.kind, density: key.density, ink: p.outline, angle: t, windy: key.windy)
            } else {
                precipitation(c, kind: key.kind, density: key.density, color: p.water, angle: t, windy: key.windy)
            }
        case .cycloneDemo:
            cyclone(c, palette: p, angle: t)
        }
    }

    private func windStreams(_ c: CGContext, palette p: Palette, angle t: CGFloat) {
        for lane in 0..<2 {
            let phase = t + CGFloat(lane) * 1.4
            let shift = 1.15 * sin(phase)
            let x = 2.6 + CGFloat(lane) * 3.9 + shift
            let y: CGFloat = lane == 0 ? 3.75 : 1.75
            let length: CGFloat = lane == 0 ? 9.8 : 6.4
            let stream = CGMutablePath()
            stream.move(to: CGPoint(x: x, y: y))
            stream.addLine(to: CGPoint(x: x + length - 1.45, y: y))
            stream.addQuadCurve(to: CGPoint(x: x + length, y: y + 0.9),
                                control: CGPoint(x: x + length, y: y))
            c.saveGState()
            c.setStrokeColor(p.water)
            c.setLineWidth(lane == 0 ? 0.98 : 0.80)
            c.setAlpha(0.81 + 0.14 * cos(phase))
            c.addPath(stream)
            c.strokePath()
            c.restoreGState()
        }
    }

    private func cyclone(_ c: CGContext, palette p: Palette, angle t: CGFloat) {
        for arm in 0..<2 {
            let spiral = CGMutablePath()
            for index in 0...20 {
                let progress = CGFloat(index) / 20
                let radius = 2.25 + 5.1 * progress
                let angle = t + CGFloat(arm) * .pi + 3.3 * progress
                let point = CGPoint(x: 9 + radius * cos(angle), y: 9 + radius * sin(angle))
                if index == 0 { spiral.move(to: point) } else { spiral.addLine(to: point) }
            }
            c.setStrokeColor(arm == 0 ? p.water : p.outline)
            c.setLineWidth(arm == 0 ? 1.55 : 1.22)
            c.addPath(spiral)
            c.strokePath()
        }
        c.setFillColor(p.cloudTop)
        c.setStrokeColor(p.outline)
        c.setLineWidth(0.9)
        c.addEllipse(in: CGRect(x: 7.75, y: 7.75, width: 2.5, height: 2.5))
        c.drawPath(using: .fillStroke)
    }

    private func sun(_ c: CGContext, x: CGFloat, y: CGFloat, scale s: CGFloat, palette p: Palette, angle t: CGFloat) {
        for i in 0..<8 {
            let a = CGFloat(i) / 8 * 2 * .pi + 0.065 * sin(t)
            let start = 5.25 * s
            let pulse: CGFloat = p.template ? 0.26 : 0.42
            let end = (6.7 + pulse * sin(t + CGFloat(i) * 0.8)) * s
            line(c, from: .init(x: x + cos(a) * start, y: y + sin(a) * start),
                 to: .init(x: x + cos(a) * end, y: y + sin(a) * end), color: p.sunRim, width: 1.18 * s)
        }
        let r = 3.68 * s
        c.setFillColor(p.sun)
        c.setStrokeColor(p.sunRim)
        c.setLineWidth((p.template ? 1.24 : 1.03) * s)
        c.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        c.drawPath(using: p.template ? .stroke : .fillStroke)
    }

    private func moon(_ c: CGContext, x: CGFloat, y: CGFloat, scale: CGFloat, palette p: Palette) {
        c.saveGState()
        c.translateBy(x: x, y: y)
        c.scaleBy(x: scale, y: scale)
        let shape = CGMutablePath()
        shape.move(to: .init(x: 1.05, y: 5.1))
        shape.addCurve(to: .init(x: -5.05, y: -0.35), control1: .init(x: -2.2, y: 5.05), control2: .init(x: -5.05, y: 2.85))
        shape.addCurve(to: .init(x: 0.0, y: -5.3), control1: .init(x: -5.05, y: -3.15), control2: .init(x: -2.75, y: -5.3))
        shape.addCurve(to: .init(x: 5.2, y: -1.6), control1: .init(x: 2.55, y: -5.3), control2: .init(x: 4.62, y: -3.75))
        shape.addCurve(to: .init(x: 1.05, y: 5.1), control1: .init(x: 1.05, y: -2.85), control2: .init(x: -0.75, y: 1.85))
        shape.closeSubpath()
        c.setFillColor(p.moon)
        c.setStrokeColor(p.moonRim)
        c.setLineWidth(p.template ? 1.20 : 1.05)
        c.addPath(shape)
        c.drawPath(using: p.template ? .stroke : .fillStroke)
        c.restoreGState()
    }

    private func cloud(_ c: CGContext, x: CGFloat, y: CGFloat, scale: CGFloat, palette p: Palette, rear: Bool = false) {
        c.saveGState()
        c.translateBy(x: x, y: y)
        c.scaleBy(x: scale, y: scale)
        let shape = CGMutablePath()
        shape.move(to: .init(x: 3.0, y: 0.0))
        shape.addCurve(to: .init(x: 0.0, y: 2.65), control1: .init(x: 1.3, y: 0.0), control2: .init(x: 0.0, y: 0.9))
        shape.addCurve(to: .init(x: 3.0, y: 5.45), control1: .init(x: 0.0, y: 4.25), control2: .init(x: 1.35, y: 5.45))
        shape.addCurve(to: .init(x: 7.0, y: 8.3), control1: .init(x: 3.45, y: 7.0), control2: .init(x: 4.95, y: 8.3))
        shape.addCurve(to: .init(x: 10.9, y: 5.7), control1: .init(x: 8.8, y: 8.3), control2: .init(x: 10.25, y: 7.25))
        shape.addCurve(to: .init(x: 14.1, y: 2.9), control1: .init(x: 12.75, y: 5.75), control2: .init(x: 14.1, y: 4.55))
        shape.addCurve(to: .init(x: 10.95, y: 0.0), control1: .init(x: 14.1, y: 1.2), control2: .init(x: 12.8, y: 0.0))
        shape.closeSubpath()
        if p.template {
            // Knock out the shape beneath the foreground cloud so overlapping outlines stay legible.
            c.saveGState()
            c.setBlendMode(.clear)
            c.addPath(shape)
            c.fillPath()
            c.restoreGState()
        } else {
            c.setFillColor(rear ? p.cloud : p.cloudTop)
        }
        c.setStrokeColor(p.outline)
        c.setLineWidth(p.template ? 1.36 : 1.12)
        c.addPath(shape)
        c.drawPath(using: p.template ? .stroke : .fillStroke)
        c.restoreGState()
    }

    private func templatePrecipitation(_ c: CGContext, kind: Kind, density: Int, ink: CGColor, angle t: CGFloat, windy: Bool) {
        let lanes: [CGFloat] = density == 2 && kind != .snow ? [4.65, 7.75, 10.85, 13.95] : [5.25, 9.25, 13.25]
        for (index, x) in lanes.enumerated() {
            let phase = t + CGFloat(index) * 1.8
            let y = 5.6 + 0.80 * sin(phase)
            let alpha = 0.87 + 0.13 * cos(phase)
            if kind == .snow {
                let drift = 0.38 * sin(phase)
                star(c, x: x + drift, y: y - 0.8, radius: 1.40, color: ink, alpha: alpha)
            } else {
                let length: CGFloat = kind == .drizzle ? 1.25 : 2.75
                line(c, from: .init(x: x + (windy ? 0.65 : 0.0), y: y),
                     to: .init(x: x - (windy ? 0.80 : 0.68), y: y - length),
                     color: ink, width: 1.24, alpha: alpha)
            }
        }
    }

    private func precipitation(_ c: CGContext, kind: Kind, density: Int, color: CGColor, angle t: CGFloat, windy: Bool) {
        let lanes: [CGFloat] = density == 2 ? [4.7, 7.9, 11.0, 14.2] : [5.6, 9.4, 13.1]
        let cycle = t / (2 * .pi)
        for (i, x) in lanes.enumerated() {
            let f = (cycle + CGFloat(i) * 0.34).truncatingRemainder(dividingBy: 1)
            let y = 7.2 - 4.6 * f
            let alpha = 0.52 + 0.48 * sin(.pi * f)
            if kind == .snow {
                let dx = 0.48 * sin(t + CGFloat(i))
                if i == 0 || (i == 2 && density > 0) {
                    star(c, x: x + dx, y: y, radius: 1.25, color: color, alpha: alpha)
                } else {
                    dot(c, x: x + dx, y: y, radius: 0.7, color: color, alpha: alpha)
                }
            } else {
                let length: CGFloat = kind == .drizzle ? 1.2 : 1.95 + 0.2 * CGFloat(density)
                let drift = windy ? 1.2 * f : 0
                let slant: CGFloat = windy ? 1.55 : 0.25
                line(c, from: .init(x: x + 0.45 - drift, y: y), to: .init(x: x - slant - drift, y: y - length),
                     color: color, width: kind == .drizzle ? 0.95 : 1.16, alpha: alpha)
            }
        }
    }

    private func star(_ c: CGContext, x: CGFloat, y: CGFloat, radius r: CGFloat, color: CGColor, alpha: CGFloat = 1) {
        let path = CGMutablePath()
        let n = r * 0.34
        path.move(to: .init(x: x, y: y + r))
        path.addLines(between: [.init(x: x + n, y: y + n), .init(x: x + r, y: y),
                                .init(x: x + n, y: y - n), .init(x: x, y: y - r),
                                .init(x: x - n, y: y - n), .init(x: x - r, y: y), .init(x: x - n, y: y + n)])
        path.closeSubpath()
        c.saveGState()
        c.setAlpha(alpha)
        c.setFillColor(color)
        c.addPath(path)
        c.fillPath()
        c.restoreGState()
    }

    private func dot(_ c: CGContext, x: CGFloat, y: CGFloat, radius: CGFloat, color: CGColor, alpha: CGFloat) {
        c.saveGState()
        c.setAlpha(alpha)
        c.setFillColor(color)
        c.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        c.restoreGState()
    }

    private func line(_ c: CGContext, from: CGPoint, to: CGPoint, color: CGColor, width: CGFloat, alpha: CGFloat = 1) {
        c.saveGState()
        c.setAlpha(alpha)
        c.setStrokeColor(color)
        c.setLineWidth(width)
        c.move(to: from)
        c.addLine(to: to)
        c.strokePath()
        c.restoreGState()
    }
}
