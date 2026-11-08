import AppKit

/// One template image lets the system tint all three parts consistently,
/// including dark menu bars and the status button's highlighted state.
@MainActor
final class MenuBarContent {
    struct Layout {
        let size: NSSize
        let weather: NSRect
        let temperature: NSRect
        let outfit: NSRect?
    }

    private struct ContentKey: Equatable {
        let temperature: String
        let outfit: ObjectIdentifier?
    }

    private struct Frame {
        // Retain the source so an evicted weather frame's identity cannot be reused.
        let weather: NSImage
        let image: NSImage
    }

    private var content: ContentKey?
    private var frames: [ObjectIdentifier: Frame] = [:]
    private var recency: [ObjectIdentifier] = []
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)

    static func layout(temperature: String, showsOutfit: Bool) -> Layout {
        let measured = (temperature as NSString).size(withAttributes: [.font: font])
        let reference = ("−8°" as NSString).size(withAttributes: [.font: font])
        let textWidth = ceil(max(reference.width, measured.width))
        let width = 4 + 18 + 2 + textWidth + (showsOutfit ? 2 + 18 : 0) + 4
        let height: CGFloat = 22
        return Layout(size: NSSize(width: width, height: height),
                      weather: NSRect(x: 4, y: 2, width: 18, height: 18),
                      temperature: NSRect(x: 24, y: (height - measured.height) / 2,
                                          width: textWidth, height: measured.height),
                      outfit: showsOutfit ? NSRect(x: 26 + textWidth, y: 2, width: 18, height: 18) : nil)
    }

    func image(weather: NSImage, temperature: String, outfit: NSImage?) -> NSImage {
        let key = ContentKey(temperature: temperature, outfit: outfit.map(ObjectIdentifier.init))
        if content != key {
            content = key
            frames.removeAll(keepingCapacity: true)
            recency.removeAll(keepingCapacity: true)
        }
        let frameID = ObjectIdentifier(weather)
        if let cached = frames[frameID] { return cached.image }
        let layout = Self.layout(temperature: temperature, showsOutfit: outfit != nil)
        let result = NSImage(size: layout.size)
        for scale in [1, 2] {
            let factor = CGFloat(scale)
            guard let context = CGContext(data: nil,
                                          width: Int(ceil(layout.size.width * factor)),
                                          height: Int(layout.size.height * factor),
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            context.scaleBy(x: factor, y: factor)
            weather.draw(in: layout.weather, from: .zero, operation: .sourceOver, fraction: 1)
            // Right-align within a three-character minimum so short temperatures
            // don't move the weather or clothing; longer negatives expand safely.
            let textWidth = (temperature as NSString).size(withAttributes: [.font: Self.font]).width
            (temperature as NSString).draw(at: NSPoint(x: layout.temperature.maxX - textWidth,
                                                      y: layout.temperature.minY),
                                          withAttributes: [.font: Self.font, .foregroundColor: NSColor.black])
            if let outfit, let rect = layout.outfit {
                outfit.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            NSGraphicsContext.restoreGraphicsState()
            if let bitmap = context.makeImage() {
                let representation = NSBitmapImageRep(cgImage: bitmap)
                representation.size = layout.size
                result.addRepresentation(representation)
            }
        }
        result.isTemplate = true
        frames[frameID] = Frame(weather: weather, image: result)
        recency.append(frameID)
        // One full 90-frame weather cycle, with a little room for transitions.
        if recency.count > 96 { frames.removeValue(forKey: recency.removeFirst()) }
        return result
    }
}
