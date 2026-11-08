import AppKit

/// A small native-glass label. The outer container trims only the glass rim;
/// the live glass view and its content stay together for native contrast treatment.
@MainActor
final class MenuAdviceSurface: NSView {
    private let glass = NSGlassEffectView()
    private let content = NSView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let edgeOutset: CGFloat
    private let radius: CGFloat = 12
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 7

    init(style: NSGlassEffectView.Style = .regular, trimEdge: Bool = true) {
        edgeOutset = trimEdge ? 3 : 0
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.shadowOpacity = 0
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        glass.style = style
        glass.cornerRadius = radius + edgeOutset
        glass.contentView = content
        addSubview(glass)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        label.isBezeled = false
        label.maximumNumberOfLines = 0
        label.usesSingleLineMode = false
        label.lineBreakMode = .byWordWrapping
        content.addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    func fittingSize(maximumWidth: CGFloat) -> NSSize {
        // The native cell includes text insets and CJK fallback metrics. Measure
        // again at the final width so severe-weather notes can wrap without clipping.
        let natural = label.cell?.cellSize ?? label.intrinsicContentSize
        let width = min(max(1, maximumWidth), ceil(natural.width) + 2 * horizontalPadding)
        let textBounds = NSRect(x: 0, y: 0, width: max(1, width - 2 * horizontalPadding), height: 10_000)
        let wrapped = label.cell?.cellSize(forBounds: textBounds) ?? natural
        return NSSize(width: width, height: ceil(wrapped.height) + 2 * verticalPadding)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds.insetBy(dx: -edgeOutset, dy: -edgeOutset)
        content.frame = glass.bounds
        label.frame = content.bounds.insetBy(dx: horizontalPadding + edgeOutset,
                                             dy: verticalPadding + edgeOutset)
    }
}
