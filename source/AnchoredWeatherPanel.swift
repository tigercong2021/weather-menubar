import AppKit
import SwiftUI

private struct WeatherPanelMaximumHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var weatherPanelMaximumHeight: CGFloat? {
        get { self[WeatherPanelMaximumHeightKey.self] }
        set { self[WeatherPanelMaximumHeightKey.self] = newValue }
    }
}

/// The screen budget is independent of the window's current content height.
@MainActor
final class WeatherPanelLimits: ObservableObject {
    @Published var maximumHeight: CGFloat?
    init(maximumHeight: CGFloat? = nil) { self.maximumHeight = maximumHeight }
}

/// Report only the currently displayed list page or complete city details.
struct WatchedWeatherNaturalHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

func watchedCityPageRanges(rowHeights: [CGFloat], availableHeight: CGFloat?,
                           spacing: CGFloat = 8, controlsHeight: CGFloat = 32) -> [Range<Int>] {
    guard !rowHeights.isEmpty else { return [] }
    let heights = rowHeights.map { $0.isFinite && $0 > 0 ? $0 : 96 }
    let gap = max(0, spacing)
    let total = heights.reduce(0, +) + CGFloat(heights.count - 1) * gap
    guard let availableHeight, availableHeight.isFinite, total > max(0, availableHeight) else {
        return [0..<heights.count]
    }
    let capacity = max(0, availableHeight - max(0, controlsHeight))
    var pages: [Range<Int>] = []
    var start = 0
    var used: CGFloat = 0
    for index in heights.indices {
        let next = heights[index] + (index == start ? 0 : gap)
        if index > start, used + next > capacity {
            pages.append(start..<index)
            start = index
            used = heights[index]
        } else {
            used += next
        }
    }
    pages.append(start..<heights.count)
    return pages
}

/// AppKit screen coordinates have their origin at the bottom. Fix the top edge
/// before choosing the height so fresh weather or AQI rows grow downwards.
func anchoredWeatherPanelFrame(button: NSRect, visibleFrame: NSRect, panelSize: NSSize,
                               gap: CGFloat = 6) -> NSRect {
    let left = visibleFrame.minX + gap
    let right = visibleFrame.maxX - gap
    let bottom = visibleFrame.minY + gap
    let top = min(button.minY, visibleFrame.maxY) - gap
    let width = max(0, min(ceil(panelSize.width), right - left))
    let height = max(0, min(ceil(panelSize.height), top - bottom))
    let x = min(max(button.midX - width / 2, left), max(left, right - width))
    return NSRect(x: x, y: top - height, width: width, height: height)
}

@MainActor
final class AnchoredWeatherPanel: NSObject {
    private static let defaultContentSize = NSSize(width: 348, height: 416)
    private static let escapeKey: UInt16 = 53
    private let window: WeatherPanelWindow
    private weak var button: NSStatusBarButton?
    private var contentSize = defaultContentSize
    private let limits = WeatherPanelLimits()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pageSwipeDistance: CGFloat = 0
    private var pageSwipeConsumed = false
    private(set) var isShown = false
    var visibilityDidChange: (() -> Void)?
    var turnPage: ((Bool) -> Bool)?

    var appearance: NSAppearance? {
        get { window.appearance }
        set { window.appearance = newValue }
    }

    init(rootView: WeatherPanel) {
        window = WeatherPanelWindow(contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
                                    styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: true)
        super.init()
        window.title = "天气"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovable = false
        window.isFloatingPanel = true
        window.level = .popUpMenu
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let host = NSHostingController(rootView: WeatherPanelViewport(content: rootView, limits: limits) { [weak self] size in
            // Apply the AppKit frame outside SwiftUI's layout transaction.
            Task { @MainActor [weak self] in self?.updateContentSize(size) }
        })
        host.sizingOptions = []
        let container = NSViewController()
        let surface = WeatherPanelSurface()
        container.view = surface
        container.addChild(host)
        let hostedView = host.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: surface.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        window.contentViewController = container
    }

    func show(below button: NSStatusBarButton) {
        guard !isShown else { return }
        self.button = button
        guard let frame = targetFrame(), frame.width > 0, frame.height > 0 else { return }
        window.setFrame(frame, display: false)
        window.makeKeyAndOrderFront(nil)
        isShown = true
        pageSwipeDistance = 0
        pageSwipeConsumed = false
        startMonitoring()
        visibilityDidChange?()
    }

    func close() {
        guard isShown else { return }
        isShown = false
        stopMonitoring()
        window.orderOut(nil)
        button = nil
        visibilityDidChange?()
    }

    private func buttonRect() -> NSRect? {
        guard let button, let parent = button.window else { return nil }
        return parent.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func targetFrame() -> NSRect? {
        guard let buttonRect = buttonRect() else { return nil }
        let center = NSPoint(x: buttonRect.midX, y: buttonRect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
                ?? button?.window?.screen ?? NSScreen.main else { return nil }
        let maximum = anchoredWeatherPanelFrame(button: buttonRect, visibleFrame: screen.visibleFrame,
                                               panelSize: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)).height
        if limits.maximumHeight != maximum { limits.maximumHeight = maximum }
        return anchoredWeatherPanelFrame(button: buttonRect, visibleFrame: screen.visibleFrame, panelSize: contentSize)
    }

    private func updateContentSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let roundedSize = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard roundedSize != contentSize else { return }
        contentSize = roundedSize
        reanchor()
    }

    @objc private func reanchor() {
        guard isShown, let frame = targetFrame(), frame.width > 0, frame.height > 0, frame != window.frame else {
            return
        }
        window.setFrame(frame, display: true)
    }

    @objc private func spaceChanged() { close() }

    private var composingText: Bool {
        (window.firstResponder as? NSTextInputClient)?.hasMarkedText() == true
    }

    private func startMonitoring() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union([.keyDown, .scrollWheel])) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleLocalEvent(event) ?? false }
            return consumed ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated {
                // The input method's candidate window can belong to another process.
                if self?.composingText == false { self?.close() }
            }
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(reanchor), name: NSApplication.didChangeScreenParametersNotification,
                           object: nil)
        if let buttonWindow = button?.window {
            center.addObserver(self, selector: #selector(reanchor), name: NSWindow.didMoveNotification,
                               object: buttonWindow)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
                                                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    private func stopMonitoring() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func handleLocalEvent(_ event: NSEvent) -> Bool {
        if event.type == .scrollWheel {
            return handlePageSwipe(event)
        }
        if event.type == .keyDown {
            if event.keyCode == Self.escapeKey, event.window === window, !composingText {
                close()
                return true
            }
            return false
        }

        if event.window === window || event.window?.parent === window { return false }
        let location = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        // Let the status item's action perform its own toggle for clicks on the anchor.
        if buttonRect()?.contains(location) != true { close() }
        return false
    }

    private func handlePageSwipe(_ event: NSEvent) -> Bool {
        guard event.window === window, event.hasPreciseScrollingDeltas else { return false }
        if event.phase.contains(.began) {
            pageSwipeDistance = 0
            pageSwipeConsumed = false
        }
        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5
        if !event.momentumPhase.isEmpty { return horizontal && pageSwipeConsumed }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            pageSwipeDistance = 0
            return false
        }
        guard horizontal else { return false }
        if !pageSwipeConsumed {
            pageSwipeDistance += event.scrollingDeltaX
            if abs(pageSwipeDistance) >= 28 {
                pageSwipeConsumed = turnPage?(pageSwipeDistance < 0) ?? false
                pageSwipeDistance = 0
            }
        }
        return pageSwipeConsumed
    }
}

private final class WeatherPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class WeatherPanelSurface: NSView {
    static let cornerRadius: CGFloat = 18
    private let material = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true

        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = Self.roundedMask()
        material.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material)
        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.topAnchor.constraint(equalTo: topAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(updateMaterial),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        updateMaterial()
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    @objc private func updateMaterial() {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        material.isHidden = reduceTransparency
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = reduceTransparency ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
        }
    }

    private static func roundedMask() -> NSImage {
        let radius = cornerRadius
        let side = 2 * radius + 2
        let mask = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }
}

private struct WeatherPanelViewport: View {
    let content: WeatherPanel
    let contentSizeDidChange: @MainActor (CGSize) -> Void
    @ObservedObject private var model: WeatherModel
    @ObservedObject private var limits: WeatherPanelLimits

    init(content: WeatherPanel, limits: WeatherPanelLimits = WeatherPanelLimits(),
         contentSizeDidChange: @escaping @MainActor (CGSize) -> Void) {
        self.content = content
        self.contentSizeDidChange = contentSizeDidChange
        _model = ObservedObject(wrappedValue: content.model)
        _limits = ObservedObject(wrappedValue: limits)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeatherPanelSurface.cornerRadius)
        GeometryReader { _ in
            if model.showsWatchedWeather {
                // Watched pages never scroll; screen overflow is handled by pages.
                content
                    .environment(\.weatherPanelMaximumHeight, limits.maximumHeight)
                    .onPreferenceChange(WatchedWeatherNaturalHeightKey.self) { height in
                        guard height.isFinite, height > 0 else { return }
                        contentSizeDidChange(CGSize(width: 348, height: height))
                    }
            } else {
                ScrollView(.vertical) {
                    content.onGeometryChange(for: CGSize.self, of: { $0.size }, action: contentSizeDidChange)
                }
                // `.hidden` may reserve a legacy scrollbar gutter on macOS.
                .scrollIndicators(.never)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
