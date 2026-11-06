import AppKit
import Combine
import Foundation
import Network
import OSLog
import ServiceManagement

enum MenuAppearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: Self { self }
    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var appKit: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum LocationMode: String, CaseIterable, Identifiable, Codable {
    case automatic, manual
    var id: Self { self }
    var label: String { self == .automatic ? "自动定位" : "手动城市" }
}

enum WeatherPanelPage: String, CaseIterable, Identifiable {
    case local = "本地天气"
    case watched = "关注城市"

    var id: Self { self }
}

private struct Preferences: Codable {
    var mode = LocationMode.automatic
    var manualPlace: WeatherPlace?
    var animate = true
    var appearance = MenuAppearance.system
}

private struct SavedWeather: Codable {
    let mode: LocationMode
    let snapshot: WeatherSnapshot
}

enum WeatherNotice: Equatable {
    case starting, permission, disabled, locating, noFix, noCity, offline, loading, failed, idle

    var text: String? {
        switch self {
        case .starting: "正在检查定位"
        case .permission: "允许定位，或手动选一个城市"
        case .disabled: "系统定位不可用，可在设置中开启"
        case .locating: "正在确认当前位置"
        case .noFix: "暂时无法取得位置"
        case .noCity: "请先选择一个城市"
        case .offline: "等待联网"
        case .loading: "正在更新天气"
        case .failed: "暂时无法更新天气，稍后自动重试"
        case .idle: nil
        }
    }
}

@MainActor
final class WeatherModel: ObservableObject {
    @Published private var preferences: Preferences
    @Published private var saved: SavedWeather?
    @Published private(set) var notice = WeatherNotice.starting
    @Published private(set) var now = Date()
    @Published private(set) var cityResults: [CityChoice] = []
    @Published private(set) var cityMessage: String?
    @Published private(set) var searching = false
    @Published var showsSettings = false
    @Published var panelPage = WeatherPanelPage.local
    @Published var showsWatchedCitySearch = false
    @Published var showsMotionPreview = false
    @Published var previewWeather = WeatherDemo.rain
    @Published var cityQuery = ""
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private var loginItemStatus: SMAppService.Status = .notRegistered
    @Published private(set) var loginItemMessage: String?
    @Published private(set) var airQuality: AirQualityReading?
    @Published private(set) var airQualityLoading = false
    @Published private(set) var airQualityUnavailable = false

    private let defaults: UserDefaults
    private let location = LocationService()
    private let weather = WeatherClient()
    private let airQualityClient = AirQualityClient()
    private let airQualityLog = Logger(subsystem: "local.tigercong.weathermenu", category: "air-quality")
    private let network = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "local.tigercong.weathermenu.network")
    private var online: Bool?
    private var active = true
    private var locationConfirmed = false
    private var target: WeatherPlace?
    private var candidate: (point: WeatherCoordinate, firstSeen: Date)?
    private var lastLocationAttempt = Date.distantPast
    private var nextLocationAttempt = Date.distantPast
    private var nextWeatherAttempt = Date.distantPast
    private var lastWeatherAttempt: TimeInterval?
    private var failures = 0
    private var generation = 0
    private var work: Task<Void, Never>?
    private var searchWork: Task<Void, Never>?
    private var searchID = 0
    private var airQualityWork: Task<Void, Never>?
    private var airQualityPlace: WeatherPlace?
    private var nextAirQualityAttempt = Date.distantPast
    private var airQualityID = 0
    private let fallbackCity = "当前位置（城市名暂不可用）"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = defaults.data(forKey: "preferences.v1")
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        self.saved = defaults.data(forKey: "weather.v1")
            .flatMap { try? JSONDecoder().decode(SavedWeather.self, from: $0) }
        self.airQuality = defaults.data(forKey: "air-quality.v1")
            .flatMap { try? JSONDecoder().decode(AirQualityReading.self, from: $0) }
        if mode == .manual {
            target = preferences.manualPlace
        } else if saved?.mode == .automatic {
            target = saved?.snapshot.place
        }
    }

    var mode: LocationMode { preferences.mode }
    var appearance: MenuAppearance { preferences.appearance }
    var animationEnabled: Bool { preferences.animate }
    var opensAtLogin: Bool { loginItemStatus == .enabled }
    var loginItemNeedsApproval: Bool { loginItemStatus == .requiresApproval }
    let canSetLoginItem: Bool = {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let directory = bundle.deletingLastPathComponent().path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return bundle.pathExtension == "app" && (directory == "/Applications" || directory == userApplications)
    }()
    var selectedCity: String? { preferences.manualPlace?.name }
    var snapshot: WeatherSnapshot? { saved?.snapshot }
    var showsWeatherDetails: Bool { !showsSettings && !showsWatchedCitySearch && !showsMotionPreview }
    var showsLocalWeather: Bool { showsWeatherDetails && panelPage == .local }
    var showsWatchedWeather: Bool { showsWeatherDetails && panelPage == .watched }

    func turnWeatherPage(forward: Bool) -> Bool {
        guard showsWeatherDetails else { return false }
        let next: WeatherPanelPage = forward ? .watched : .local
        if panelPage != next { panelPage = next }
        return true
    }
    var visibleAirQuality: AirQualityReading? {
        guard let airQuality, !hasLastPlace, airQuality.place == snapshot?.place,
              airQuality.age(at: now) < 6 * 3600 else { return nil }
        return airQuality
    }
    var hasLastPlace: Bool {
        guard let saved else { return false }
        if saved.mode != mode || saved.snapshot.place != target { return true }
        return mode == .automatic && !locationConfirmed
    }
    var age: TimeInterval { snapshot?.age(at: now) ?? .infinity }
    var showMenuTemperature: Bool { snapshot != nil && age < 6 * 3600 }
    var isStale: Bool { age >= 30 * 60 }
    var showWeatherIcon: Bool { snapshot != nil && age < 2 * 3600 }
    var canAnimate: Bool {
        showWeatherIcon && animationEnabled && !hasLastPlace && snapshot?.isDay(at: now) != nil
            && WeatherKind(code: snapshot?.code) != .unknown
    }

    func start() {
        if CommandLine.arguments.contains("--enable-login-item") {
            setOpensAtLogin(true)
        }
        location.onAuthorizationChange = { [weak self] _ in
            self?.authorizationChanged()
        }
        network.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(available) }
        }
        network.start(queue: networkQueue)
        pulse()
    }

    func refreshLoginItemStatus() {
        guard canSetLoginItem else { return }
        let status = SMAppService.mainApp.status
        if status != loginItemStatus {
            loginItemStatus = status
            loginItemMessage = nil
        }
    }

    func setOpensAtLogin(_ enabled: Bool) {
        guard canSetLoginItem else { return }
        refreshLoginItemStatus()
        guard enabled != opensAtLogin, !loginItemNeedsApproval else { return }
        loginItemMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            refreshLoginItemStatus()
            if enabled != opensAtLogin && !loginItemNeedsApproval {
                loginItemMessage = "未能修改登录启动，请在系统设置中检查。"
                let error = error as NSError
                let log = Logger(subsystem: "local.tigercong.weathermenu", category: "login-item")
                log.error("Login item update failed: \(error.domain, privacy: .public) (\(error.code, privacy: .public))")
            }
            return
        }
        refreshLoginItemStatus()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func pulse() {
        now = Date()
        runIfNeeded()
        refreshAirQualityIfNeeded()
    }

    func suspend() {
        active = false
        invalidateWork()
    }

    func resume() {
        active = true
        nextLocationAttempt = .distantPast
        if age >= 15 * 60 { nextWeatherAttempt = .distantPast }
        pulse()
    }

    func systemClockChanged() {
        nextLocationAttempt = .distantPast
        nextWeatherAttempt = .distantPast
        candidate = nil
        nextAirQualityAttempt = .distantPast
        pulse()
    }

    func refresh() {
        guard work == nil else { return }
        nextLocationAttempt = .distantPast
        nextWeatherAttempt = .distantPast
        pulse()
    }

    func setMode(_ mode: LocationMode) {
        guard self.mode != mode else { return }
        invalidateWork()
        preferences.mode = mode
        savePreferences()
        target = mode == .manual ? preferences.manualPlace : nil
        locationConfirmed = false
        candidate = nil
        nextLocationAttempt = .distantPast
        nextWeatherAttempt = .distantPast
        failures = 0
        pulse()
    }

    func setAnimation(_ enabled: Bool) {
        preferences.animate = enabled
        savePreferences()
    }

    func setAppearance(_ appearance: MenuAppearance) {
        preferences.appearance = appearance
        savePreferences()
    }

    func updatePowerMode() {
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        if lowPowerMode != enabled { lowPowerMode = enabled }
    }

    func resetCitySearch() {
        searchID += 1
        searchWork?.cancel()
        searchWork = nil
        cityQuery = ""
        cityResults = []
        cityMessage = nil
        searching = false
    }

    func setCityMessage(_ message: String) { cityMessage = message }

    func allowLocation() {
        guard mode == .automatic, location.authorization == .notDetermined else { return }
        location.requestAuthorization()
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func searchCities(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchID += 1
        let id = searchID
        searchWork?.cancel()
        searchWork = nil
        cityResults = []
        cityMessage = nil
        searching = false
        guard !trimmed.isEmpty else { cityMessage = "请输入城市名"; return }
        guard online != false else { cityMessage = "联网后可搜索城市"; return }
        searching = true
        searchWork = Task { [weak self] in
            do {
                let appleChoices = (try? await CityLookup.search(trimmed)) ?? []
                try Task.checkCancellation()
                let choices = appleChoices.isEmpty ? try await CitySearchFallback.search(trimmed) : appleChoices
                guard let self, !Task.isCancelled, searchID == id else { return }
                cityResults = choices
                cityMessage = choices.isEmpty ? "没找到城市，试试中英文城市名或加上国家" : nil
                searching = false
            } catch {
                guard let self, !Task.isCancelled, searchID == id else { return }
                cityMessage = "城市搜索暂时不可用，请稍后重试"
                searching = false
            }
        }
    }

    func chooseCity(_ city: CityChoice) {
        let place = WeatherPlace(name: city.name, coordinate: WeatherCoordinate(latitude: city.latitude,
                                                                                longitude: city.longitude))
        invalidateWork()
        preferences.mode = .manual
        preferences.manualPlace = place
        target = place
        locationConfirmed = false
        candidate = nil
        cityResults = []
        cityMessage = nil
        savePreferences()
        failures = 0
        nextWeatherAttempt = .distantPast
        pulse()
    }

    private func savePreferences() {
        if let bytes = try? JSONEncoder().encode(preferences) {
            defaults.set(bytes, forKey: "preferences.v1")
        }
    }

    private func invalidateWork() {
        generation += 1
        work?.cancel()
        work = nil
        cancelAirQuality()
    }

    private func authorizationChanged() {
        guard mode == .automatic else { return }
        if location.authorization != .authorized {
            invalidateWork()
            locationConfirmed = false
        }
        nextLocationAttempt = .distantPast
        pulse()
    }

    private func networkChanged(_ available: Bool) {
        let wasOnline = online
        online = available
        if available, wasOnline == false {
            nextLocationAttempt = .distantPast
            if age >= 15 * 60 || hasLastPlace || failures > 0 {
                nextWeatherAttempt = .distantPast
            }
            if visibleAirQuality == nil { nextAirQualityAttempt = .distantPast }
        }
        pulse()
    }

    private func runIfNeeded() {
        guard active else { return }
        if mode == .automatic {
            switch location.authorization {
            case .notDetermined: notice = .permission; return
            case .denied, .restricted: notice = .disabled; return
            case .authorized: break
            }
        }
        guard work == nil else { return }
        if mode == .automatic, now >= nextLocationAttempt {
            beginLocation()
            return
        }
        if mode == .automatic, !locationConfirmed {
            if notice == .locating || notice == .permission || notice == .disabled {
                notice = .noFix
            }
            return
        }
        guard let target else {
            notice = .noCity
            return
        }
        guard online != false else {
            notice = .offline
            return
        }
        guard now >= nextWeatherAttempt else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        if let lastWeatherAttempt, uptime - lastWeatherAttempt < 30 { return }
        beginWeather(target, uptime: uptime)
    }

    private func beginLocation() {
        let id = generation
        notice = .locating
        lastLocationAttempt = now
        nextLocationAttempt = now.addingTimeInterval(12 * 60)
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let fix = try await location.fix()
                guard isCurrent(id) else { return }
                await accept(fix, generation: id)
            } catch {
                guard isCurrent(id) else { return }
                locationConfirmed = false
                notice = .noFix
                nextLocationAttempt = Date().addingTimeInterval(3 * 60)
            }
            guard isCurrent(id) else { return }
            work = nil
            pulse()
        }
    }

    private func accept(_ fix: LocationFix, generation id: Int) async {
        let point = WeatherCoordinate(latitude: fix.latitude, longitude: fix.longitude)
        if let target {
            let distance = point.distance(to: target.coordinate)
            let threshold = max(8_000, fix.accuracy * 2)
            if distance < threshold, target.name != fallbackCity {
                candidate = nil
                locationConfirmed = true
                notice = online == false ? .offline : .idle
                return
            }
            if distance >= threshold, distance < 24_000 {
                if let candidate,
                   point.distance(to: candidate.point) < max(9_000, fix.accuracy * 2),
                   Date().timeIntervalSince(candidate.firstSeen) >= 30 {
                    self.candidate = nil
                } else {
                    candidate = (point, lastLocationAttempt)
                    locationConfirmed = false
                    nextLocationAttempt = Date().addingTimeInterval(45)
                    notice = .locating
                    return
                }
            }
        }
        var city: String?
        if online != false {
            city = try? await CityLookup.reverse(fix)
        }
        guard isCurrent(id) else { return }
        let revised = WeatherPlace(name: city ?? fallbackCity, coordinate: point)
        if revised != target {
            target = revised
            nextWeatherAttempt = .distantPast
            failures = 0
        }
        candidate = nil
        locationConfirmed = true
        notice = online == false ? .offline : .loading
    }

    private func beginWeather(_ place: WeatherPlace, uptime: TimeInterval) {
        let id = generation
        let requestedMode = mode
        lastWeatherAttempt = uptime
        notice = .loading
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let incoming = try await weather.fetch(for: place)
                guard isCurrent(id) else { return }
                guard target == place, incoming.place == place else {
                    work = nil
                    postponeWeather()
                    return
                }
                if let old = saved, old.mode == requestedMode, old.snapshot.place == place,
                   incoming.validAt < old.snapshot.validAt {
                    postponeWeather()
                } else {
                    let accepted = SavedWeather(mode: requestedMode, snapshot: incoming)
                    saved = accepted
                    if let bytes = try? JSONEncoder().encode(accepted) {
                        defaults.set(bytes, forKey: "weather.v1")
                    }
                    failures = 0
                    nextWeatherAttempt = Date().addingTimeInterval(15 * 60)
                    notice = .idle
                }
            } catch {
                guard isCurrent(id) else { return }
                postponeWeather()
            }
            work = nil
            now = Date()
            refreshAirQualityIfNeeded()
        }
    }

    private func postponeWeather() {
        failures = min(failures + 1, 5)
        nextWeatherAttempt = Date().addingTimeInterval(min(15 * 60, 30 * pow(2, Double(failures))))
        notice = online == false ? .offline : .failed
    }

    private func isCurrent(_ id: Int) -> Bool {
        generation == id && !Task.isCancelled
    }

    private func refreshAirQualityIfNeeded() {
        guard active, online != false, !hasLastPlace, let place = snapshot?.place else {
            cancelAirQuality()
            return
        }
        if airQualityPlace != place {
            cancelAirQuality()
            airQualityPlace = place
            nextAirQualityAttempt = .distantPast
            airQualityUnavailable = false
        }
        guard airQualityWork == nil, now >= nextAirQualityAttempt else { return }
        if let reading = visibleAirQuality, now.timeIntervalSince(reading.fetchedAt) < 30 * 60 {
            nextAirQualityAttempt = reading.fetchedAt.addingTimeInterval(30 * 60)
            return
        }

        let id = airQualityID
        airQualityLoading = true
        airQualityUnavailable = false
        nextAirQualityAttempt = now.addingTimeInterval(90)
        airQualityWork = Task { [weak self] in
            guard let self else { return }
            defer {
                if airQualityID == id {
                    airQualityWork = nil
                    airQualityLoading = false
                }
            }
            do {
                let reading = try await airQualityClient.fetch(for: place)
                guard !Task.isCancelled, airQualityID == id, !hasLastPlace,
                      target == place, reading.place == place else { return }
                if let old = airQuality, old.place == place, old.validAt > reading.validAt { return }
                airQuality = reading
                nextAirQualityAttempt = Date().addingTimeInterval(30 * 60)
                if let bytes = try? JSONEncoder().encode(reading) {
                    defaults.set(bytes, forKey: "air-quality.v1")
                }
            } catch {
                guard !Task.isCancelled, airQualityID == id else { return }
                airQualityUnavailable = true
                let failure = error as NSError
                airQualityLog.notice("Air quality fetch failed: \(failure.domain, privacy: .public) (\(failure.code, privacy: .public))")
            }
        }
    }

    private func cancelAirQuality() {
        guard airQualityWork != nil else { return }
        airQualityID += 1
        airQualityWork?.cancel()
        airQualityWork = nil
        airQualityLoading = false
    }
}

func temperatureText(_ value: Double?) -> String {
    guard let value, value.isFinite, abs(value) < 200 else { return "—" }
    return String(Int(value.rounded())).replacingOccurrences(of: "-", with: "−") + "°"
}
