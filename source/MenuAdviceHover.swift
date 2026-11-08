import AppKit

/// A single, cancellable hover delay independent of weather animation frames.
@MainActor
final class MenuHoverTrigger {
    private let delay: Duration
    private let show: (String) -> Void
    private let hide: () -> Void
    private var text: String?
    private var enabled = false
    private var hovering = false
    private var visible = false
    private var pending: Task<Void, Never>?

    init(delay: Duration = .milliseconds(450), show: @escaping (String) -> Void,
         hide: @escaping () -> Void) {
        self.delay = delay
        self.show = show
        self.hide = hide
    }

    func update(text: String?, enabled: Bool) {
        let next = text.flatMap { $0.isEmpty ? nil : $0 }
        let changed = self.text != next
        self.text = next
        self.enabled = enabled && next != nil
        guard self.enabled else {
            // Invalid data, sleeping, or an open details panel require a fresh
            // pointer entry before another suggestion can appear.
            dismiss()
            return
        }
        if visible, changed, let next { show(next) }
        // Ordinary model refreshes never restart a pending delay or reopen a
        // tooltip dismissed by clicking the status button.
    }

    func enter() {
        guard !hovering else { return }
        hovering = true
        guard enabled, text != nil else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak self, delay] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled, self.hovering, self.enabled,
                  let text = self.text else { return }
            self.pending = nil
            self.visible = true
            self.show(text)
        }
    }

    func exit() { dismiss() }

    func dismiss() {
        hovering = false
        pending?.cancel()
        pending = nil
        if visible { visible = false; hide() }
    }
}

func menuAdviceFrame(anchor: NSRect, visibleFrame: NSRect, contentSize: NSSize) -> NSRect {
    let marginX = min(6, max(0, visibleFrame.width / 2))
    let marginY = min(6, max(0, visibleFrame.height / 2))
    let left = visibleFrame.minX + marginX
    let right = visibleFrame.maxX - marginX
    let bottom = visibleFrame.minY + marginY
    let top = max(bottom, min(anchor.minY, visibleFrame.maxY) - marginY)
    let width = max(0, min(ceil(contentSize.width), right - left))
    let height = max(0, min(ceil(contentSize.height), top - bottom))
    let x = min(max(anchor.midX - width / 2, left), max(left, right - width))
    return NSRect(x: x, y: top - height, width: width, height: height)
}

/// Native status-item tooltips may not appear consistently on a menu-only app.
/// Track the whole existing button without an overlay or intercepted clicks.
@MainActor
final class MenuAdviceHover: NSObject {
    private weak var button: NSStatusBarButton?
    private var tracking: NSTrackingArea?
    private let popup = MenuAdviceWindow(contentRect: .zero,
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: true)
    private let surface = MenuAdviceSurface()
    private lazy var trigger = MenuHoverTrigger(show: { [weak self] text in self?.present(text) },
                                                hide: { [weak self] in self?.popup.orderOut(nil) })

    var appearance: NSAppearance? {
        get { popup.appearance }
        set { popup.appearance = newValue }
    }

    override init() {
        super.init()
        popup.isReleasedWhenClosed = false
        popup.isOpaque = false
        popup.backgroundColor = .clear
        popup.hasShadow = false
        popup.level = .popUpMenu
        popup.hidesOnDeactivate = false
        popup.ignoresMouseEvents = true
        popup.animationBehavior = .none
        popup.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        popup.contentView = surface
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged),
                                                name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(environmentChanged),
                                                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    func attach(to button: NSStatusBarButton) {
        dismiss()
        if let previous = self.button, let tracking { previous.removeTrackingArea(tracking) }
        self.button = button
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        button.addTrackingArea(area)
        tracking = area
    }

    func update(text: String?, enabled: Bool) { trigger.update(text: text, enabled: enabled) }
    func dismiss() { trigger.dismiss(); popup.orderOut(nil) }

    @objc private func mouseEntered(_ event: NSEvent) { trigger.enter() }
    @objc private func mouseExited(_ event: NSEvent) { trigger.exit() }
    @objc private func environmentChanged(_ notification: Notification) { dismiss() }

    private func present(_ text: String) {
        guard let button, let window = button.window else { dismiss(); return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        // Revalidate at display time: an exit, click, screen move, or hiding menu
        // bar must not leave a delayed hint at the old screen position.
        guard anchor.contains(NSEvent.mouseLocation), window.isVisible,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) })
                ?? window.screen else { dismiss(); return }
        surface.text = text
        let size = surface.fittingSize(maximumWidth: min(320, screen.visibleFrame.width - 12))
        let frame = menuAdviceFrame(anchor: anchor, visibleFrame: screen.visibleFrame, contentSize: size)
        guard frame.width > 0, frame.height > 0 else { dismiss(); return }
        popup.setFrame(frame, display: false)
        surface.frame = NSRect(origin: .zero, size: frame.size)
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        popup.orderFrontRegardless()
    }
}

private final class MenuAdviceWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
