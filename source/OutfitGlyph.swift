import AppKit

/// Approved compact clothing artwork, mapped from its complete 48-unit canvas to 18 points.
/// AppKit drawing and the small image cache stay on the UI actor.
@MainActor
final class OutfitGlyph {
    static let shared = OutfitGlyph()
    static let pointSize: CGFloat = 18

    private static let validNames: Set<String> = [
        "short-sleeve", "long-sleeve", "knit", "trousers", "shorts",
        "light-jacket", "shell", "puffer", "sun-hat", "sunglasses",
        "umbrella", "scarf", "beanie", "gloves", "boots"
    ]

    private let directoryURL: URL?
    private var images: [String: NSImage] = [:]
    private var unavailable: Set<String> = []

    init(bundle: Bundle = .main) {
        directoryURL = bundle.resourceURL?.appendingPathComponent("OutfitIcons", isDirectory: true)
    }

    /// Allows an isolated local fixture directory without changing production resource lookup.
    init(directoryURL: URL) {
        self.directoryURL = directoryURL.isFileURL ? directoryURL : nil
    }

    /// Returns a cached template image, or nil for unknown, missing, or unreadable artwork.
    func image(named name: String) -> NSImage? {
        guard Self.validNames.contains(name) else { return nil }
        if let image = images[name] { return image }
        guard !unavailable.contains(name) else { return nil }
        guard let directoryURL,
              let vector = NSImage(contentsOf: directoryURL.appendingPathComponent(name).appendingPathExtension("svg")),
              vector.isValid,
              let image = template(from: vector) else {
            unavailable.insert(name)
            return nil
        }
        images[name] = image
        return image
    }

    private func template(from vector: NSImage) -> NSImage? {
        let size = NSSize(width: Self.pointSize, height: Self.pointSize)
        let image = NSImage(size: size)
        for scale in [1, 2] {
            let pixels = Int(Self.pointSize) * scale
            guard let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return nil }
            context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            context.setShouldAntialias(true)
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            // Preserve the approved canvas margins and garment proportions. In particular,
            // do not crop to nontransparent pixels or normalize the visible silhouette.
            vector.draw(in: NSRect(origin: .zero, size: size), from: .zero,
                        operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()

            guard let bitmap = context.makeImage(),
                  let bytes = context.data?.assumingMemoryBound(to: UInt8.self),
                  (0..<(pixels * pixels)).contains(where: { bytes[$0 * 4 + 3] > 0 }) else { return nil }
            let representation = NSBitmapImageRep(cgImage: bitmap)
            representation.size = size
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        return image
    }
}
