import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum WeatherMenuApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = MenuController()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class WeatherMotion: ObservableObject {
    static let sceneDuration = 12.0

    struct Frame: Equatable {
        let panel: Int
        let menu: Int
        let sceneCycle: Double
        let sceneElapsed: Double
    }

    @Published private(set) var frame = Frame(panel: 0, menu: 0, sceneCycle: 0, sceneElapsed: 0)
    var phase: Int { frame.panel }
    var sceneCycle: Double { frame.sceneCycle }
    var sceneElapsed: Double { frame.sceneElapsed }

    func display(_ phase: Int, menu: Int? = nil, sceneCycle: Double? = nil, sceneElapsed: Double? = nil) {
        let cycle = sceneCycle ?? Double(phase) / Double(WeatherIconRenderer.frameCount)
        let next = Frame(panel: phase, menu: menu ?? phase, sceneCycle: cycle,
                         sceneElapsed: sceneElapsed ?? cycle * Self.sceneDuration)
        if frame != next { frame = next }
    }
}

@MainActor
private final class MenuController: NSObject, NSApplicationDelegate {
    private enum PanelScene: Equatable {
        case live(Int, Bool?, Bool)
        case demo(WeatherDemo)
        case watched(WeatherPlace?)
    }

    private let model = WeatherModel()
    private let watched = WatchedCities()
    private let renderer = WeatherIconRenderer()
    private let menuContent = MenuBarContent()
    private let adviceHover = MenuAdviceHover()
    private let panelMotion = WeatherMotion()
    private lazy var detailsPanel = AnchoredWeatherPanel(
        rootView: WeatherPanel(model: model, watched: watched, motion: panelMotion, renderer: renderer)
    )
    private var status: NSStatusItem?
    private var displayedTemperature = "—"
    private var displayedOutfit: NSImage?
    private var accessibilityText: String?
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var animationTimer: Timer?
    private var menuPhase = 0
    private var menuEpoch: TimeInterval?
    private var panelEpoch: TimeInterval?
    private var panelScene: PanelScene?
    private var asleep = false
    private var screenAsleep = false
    private var sessionInactive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = NSStatusBar.system.statusItem(withLength: 65)
        self.status = status
        if let button = status.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            button.setAccessibilityLabel("天气菜单栏")
            adviceHover.attach(to: button)
        }
        detailsPanel.visibilityDidChange = { [weak self] in
            self?.adviceHover.dismiss()
            self?.render()
        }
        detailsPanel.turnPage = { [weak self] forward in
            self?.model.turnWeatherPage(forward: forward) ?? false
        }
        model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.render() }
        }.store(in: &subscriptions)
        watched.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.render() }
        }.store(in: &subscriptions)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenWillSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidResign), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidActivate), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(powerChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
        center.addObserver(self, selector: #selector(clockChanged), name: .NSSystemClockDidChange, object: nil)
        center.addObserver(self, selector: #selector(clockChanged), name: .NSSystemTimeZoneDidChange, object: nil)

        let timer = Timer(timeInterval: 15, target: self, selector: #selector(pulse), userInfo: nil, repeats: true)
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        model.start()
        render()
    }

    @objc private func togglePopover() {
        adviceHover.dismiss()
        guard let button = status?.button else { return }
        if detailsPanel.isShown {
            detailsPanel.close()
        } else {
            if model.showsSettings { model.refreshLoginItemStatus() }
            model.openPanelRefresh()
            detailsPanel.show(below: button)
        }
    }

    @objc private func pulse() {
        if !asleep {
            model.pulse()
            watched.refreshIfNeeded()
        }
    }

    @objc private func systemWillSleep() {
        asleep = true
        detailsPanel.close()
        model.suspend()
        render()
    }

    @objc private func systemDidWake() {
        asleep = false
        model.resume()
        render()
    }

    @objc private func screenWillSleep() { screenAsleep = true; render() }
    @objc private func screenDidWake() { screenAsleep = false; render() }
    @objc private func sessionDidResign() { sessionInactive = true; render() }
    @objc private func sessionDidActivate() { sessionInactive = false; render() }
    @objc private func accessibilityChanged() { render() }
    @objc private func powerChanged() {
        model.updatePowerMode()
        render()
    }
    @objc private func clockChanged() { if !asleep { model.systemClockChanged() } }

    private func render() {
        let detailsVisible = !asleep && detailsPanel.isShown && model.showsWatchedWeather
        watched.setVisible(detailsVisible)
        let appearance = model.appearance.appKit
        if detailsPanel.appearance?.name != appearance?.name { detailsPanel.appearance = appearance }
        if adviceHover.appearance?.name != appearance?.name { adviceHover.appearance = appearance }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let wantsAnimation = !reduceMotion && !model.lowPowerMode && !asleep && !screenAsleep
            && !sessionInactive && (showsAnimatedPanel || animatesMenuIcon)
        let nextScene = currentPanelScene
        if nextScene != panelScene {
            panelScene = nextScene
            panelEpoch = nil
            panelMotion.display(0, menu: menuPhase)
        }
        scheduleAnimation(enabled: wantsAnimation, panelVisible: showsAnimatedPanel)

        let value = model.showMenuTemperature ? temperatureText(model.snapshot?.temperature) : "—"
        let advice = model.menuOutfitAdvice
        displayedTemperature = value
        displayedOutfit = advice.flatMap { OutfitGlyph.shared.image(named: $0.iconName) }
        let accessibilityValue: String
        if model.showMenuTemperature, let snapshot = model.snapshot {
            let qualifier = model.hasLastPlace || model.isStale ? "上次数据，" : ""
            accessibilityValue = qualifier + snapshot.place.name + "，" + value
                + (advice.map { "\n" + $0.tooltip } ?? "")
        } else {
            accessibilityValue = model.notice.text ?? "暂无当前天气"
        }
        if let button = status?.button {
            if accessibilityText != accessibilityValue {
                accessibilityText = accessibilityValue
                button.setAccessibilityValue(accessibilityValue)
            }
            // Custom hover is independent of the frequently animated button image.
            // Avoid a second, delayed system tooltip appearing over it.
            button.toolTip = nil
        }
        let hoverText = advice.map {
            let summary = $0.menuSummary + (model.isStale ? " · 上次数据" : "")
            return [summary, $0.weatherNote].compactMap { $0 }.joined(separator: "\n")
        }
        adviceHover.update(text: hoverText,
                           enabled: displayedOutfit != nil && status?.isVisible == true
                               && !detailsPanel.isShown && !asleep && !screenAsleep && !sessionInactive)
        paintFrame()
    }

    private var showsAnimatedPanel: Bool {
        detailsPanel.isShown && (
            model.showsLocalWeather && model.canAnimate || model.showsMotionPreview && model.animationEnabled
                || model.showsWatchedWeather && model.animationEnabled && !watched.places.isEmpty
        )
    }

    private var currentPanelScene: PanelScene? {
        guard detailsPanel.isShown else { return nil }
        if model.showsMotionPreview { return .demo(model.previewWeather) }
        if model.showsWatchedWeather { return .watched(watched.selectedPlace) }
        if model.showsLocalWeather, let snapshot = model.snapshot {
            return .live(snapshot.code, snapshot.isDay(at: model.now), snapshot.hasMixedPrecipitation)
        }
        return nil
    }

    private func scheduleAnimation(enabled: Bool, panelVisible: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if !enabled {
            animationTimer?.invalidate()
            animationTimer = nil
            menuEpoch = nil
            menuPhase = 0
        } else if menuEpoch == nil {
            menuEpoch = now
        }

        if !enabled || !panelVisible {
            panelEpoch = nil
            panelMotion.display(0)
        } else if panelEpoch == nil {
            panelEpoch = now
        }
        guard enabled else { return }

        let panelFramesPerSecond = model.showsWatchedWeather ? 24.0 : 30.0
        let interval = 1.0 / (panelVisible ? panelFramesPerSecond : WeatherIconRenderer.menuFramesPerSecond)
        guard animationTimer?.timeInterval != interval else { return }
        animationTimer?.invalidate()
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(advanceFrame),
                          userInfo: nil, repeats: true)
        timer.tolerance = interval * 0.10
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    @objc private func advanceFrame() {
        guard let menuEpoch else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let nextMenuPhase = Int(max(0, now - menuEpoch) * WeatherIconRenderer.menuFramesPerSecond)
            % WeatherIconRenderer.menuFrameCount
        if menuPhase != nextMenuPhase {
            menuPhase = nextMenuPhase
            if animatesMenuIcon { paintFrame() }
        }
        guard let panelEpoch else { return }
        let elapsed = max(0, now - panelEpoch)
        let panelPhase = Int(elapsed * 12) % WeatherIconRenderer.frameCount
        let cycle = elapsed.truncatingRemainder(dividingBy: WeatherMotion.sceneDuration) / WeatherMotion.sceneDuration
        panelMotion.display(panelPhase, menu: menuPhase, sceneCycle: cycle, sceneElapsed: elapsed)
    }

    private var tempsMenuIcon: NSImage? {
        guard model.showWeatherIcon, let snapshot = model.snapshot else { return nil }
        return TempsWeatherGlyph.image(code: snapshot.code, isDay: snapshot.isDay(at: model.now),
                                      size: 18, phase: model.canAnimate ? menuPhase : 0)
    }

    private var animatesMenuIcon: Bool {
        model.canAnimate && status?.isVisible == true
    }

    private func paintFrame() {
        guard let button = status?.button else { return }
        let snapshot = model.showWeatherIcon ? model.snapshot : nil
        let frame = tempsMenuIcon ?? renderer.image(code: snapshot?.code, isDay: snapshot?.isDay(at: model.now),
                                   intensity: snapshot?.intensity ?? 0, phase: model.canAnimate ? menuPhase : 0,
                                   dark: false, gust: snapshot?.gust, template: true)
        let content = menuContent.image(weather: frame, temperature: displayedTemperature,
                                        outfit: displayedOutfit)
        if status?.length != content.size.width { status?.length = content.size.width }
        if button.image !== content { button.image = content }
    }
}
