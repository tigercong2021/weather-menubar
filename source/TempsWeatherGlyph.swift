import AppKit

/// Native template images from the weather-iconic symbols used by temps v2.
/// Asset attribution and CC BY-SA 3.0 US terms accompany the bundled SVGs.
@MainActor
enum TempsWeatherGlyph {
    private struct Key: Hashable {
        let name: String
        let side: Int
    }

    private struct Symbol {
        let bitmap: CGImage
        let visible: CGRect
    }

    private static let sampleSide = 264
    private static let sampleBounds = CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide)
    private static var symbols: [String: Symbol] = [:]
    private static var images: [Key: [Int: NSImage]] = [:]
    private static var recency: [Key] = []

    static func image(code: Int?, isDay: Bool?, size: CGFloat, cycloneDemo: Bool = false,
                      phase: Int = 0) -> NSImage? {
        guard (1...256).contains(size) else { return nil }
        let name: String
        if cycloneDemo {
            name = "hurricane"
        } else {
            guard let code, let isDay else { return nil }
            name = symbol(for: code, isDay: isDay)
        }

        let side = Int(size.rounded())
        let key = Key(name: name, side: side)
        let count = WeatherIconRenderer.menuFrameCount
        let frame = side == 18 && name != "na" ? (phase % count + count) % count : 0
        recency.removeAll { $0 == key }
        recency.append(key)
        if let image = images[key]?[frame] { return image }
        guard let symbol = load(name), let image = template(symbol, key: key, frame: frame, count: count) else {
            recency.removeLast()
            return nil
        }
        images[key, default: [:]][frame] = image
        if recency.count > 24 { images.removeValue(forKey: recency.removeFirst()) }
        return image
    }

    private static func load(_ name: String) -> Symbol? {
        if let symbol = symbols[name] { return symbol }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "TempsWeather"),
              let vector = NSImage(contentsOf: url),
              let context = bitmapContext(pixels: sampleSide) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        vector.draw(in: sampleBounds, from: .zero, operation: .sourceOver, fraction: 1)
        guard let bitmap = context.makeImage(),
              let visible = opaqueBounds(in: context, side: sampleSide) else { return nil }
        let symbol = Symbol(bitmap: bitmap, visible: visible)
        symbols[name] = symbol
        return symbol
    }

    private static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun" : "moon"
        case 1: isDay ? "sun-high" : "moon"
        case 2: isDay ? "sun-cloud" : "moon-cloud"
        case 3: "clouds"
        case 45: isDay ? "sun-fog" : "moon-fog"
        case 48: "fog"
        case 51, 53, 55: "cloud-rain-alt"
        case 56, 57, 66, 67: "cloud-sleet"
        case 61, 63, 65: "cloud-rain"
        case 71, 73, 75: "cloud-snow"
        case 77: "cloud-snow-alt"
        case 80, 81, 82: isDay ? "sun-cloud-rain" : "moon-cloud-rain"
        case 85, 86: isDay ? "sun-cloud-snow" : "moon-cloud-snow"
        case 95, 97: isDay ? "sun-cloud-lightning" : "moon-cloud-lightning"
        case 96, 99: "cloud-hail"
        default: "na"
        }
    }

    private static func template(_ symbol: Symbol, key: Key, frame: Int, count: Int) -> NSImage? {
        // Match the tray's visible-box normalization; cache a higher-resolution
        // native raster so AppKit does not decode the vector on every frame.
        let tray = key.side == 18
        let bounds = tray ? symbol.visible : sampleBounds
        let pose = tray ? motion(for: key.name, frame: frame, count: count) : .identity
        let result = NSImage(size: NSSize(width: key.side, height: key.side))
        for scale in [1, 2] {
            let pixels = key.side * scale
            let center = CGFloat(pixels) / 2
            // Leave room for a one-point sway inside the menu bar's fixed 18-point image.
            let fit = CGFloat(pixels) * (tray ? 0.84 : 1) / max(bounds.width, bounds.height)
            let rect = CGRect(x: center - bounds.midX * fit, y: center - bounds.midY * fit,
                              width: sampleBounds.width * fit, height: sampleBounds.height * fit)
            // Apply rotation about the centre, in bitmap coordinates.
            let centered = CGAffineTransform(translationX: -center, y: -center)
                .concatenating(CGAffineTransform(a: pose.a, b: pose.b, c: pose.c, d: pose.d, tx: 0, ty: 0))
                .concatenating(CGAffineTransform(translationX: center + pose.tx * CGFloat(scale),
                                                 y: center + pose.ty * CGFloat(scale)))
            guard let context = bitmapContext(pixels: pixels) else { return nil }
            context.interpolationQuality = .high
            context.concatenate(centered)
            context.draw(symbol.bitmap, in: rect)
            guard let bitmap = context.makeImage() else { return nil }
            let representation = NSBitmapImageRep(cgImage: bitmap)
            representation.size = result.size
            result.addRepresentation(representation)
        }
        result.isTemplate = true
        return result
    }

    private static func motion(for name: String, frame: Int, count: Int) -> CGAffineTransform {
        let angle = CGFloat(frame) / CGFloat(count) * 2 * .pi
        let wave = sin(angle)
        switch name {
        case "sun", "sun-high":
            return CGAffineTransform(rotationAngle: 0.14 * wave)
        case "moon":
            return CGAffineTransform(rotationAngle: 0.12 * wave).translatedBy(x: 0, y: 0.35 * wave)
        case "hurricane":
            return CGAffineTransform(rotationAngle: 0.23 * wave)
        case "na":
            return .identity
        default:
            let wet = ["rain", "snow", "sleet", "hail", "lightning"].contains { name.contains($0) }
            return CGAffineTransform(translationX: (wet ? 0.56 : 1.00) * wave,
                                     y: wet ? 0.60 * cos(angle) : 0)
        }
    }

    private static func bitmapContext(pixels: Int) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                         space: colorSpace,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    }

    private static func opaqueBounds(in context: CGContext, side: Int) -> CGRect? {
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var left = side, top = side, right = -1, bottom = -1
        for row in 0..<side {
            for x in 0..<side where data[row * context.bytesPerRow + x * 4 + 3] > 12 {
                left = min(left, x)
                top = min(top, row)
                right = max(right, x)
                bottom = max(bottom, row)
            }
        }
        guard right >= left, bottom >= top else { return nil }
        return CGRect(x: left, y: side - 1 - bottom, width: right - left + 1, height: bottom - top + 1)
    }
}
