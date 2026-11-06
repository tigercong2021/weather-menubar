import SwiftUI

struct WeatherPanel: View {
    @ObservedObject var model: WeatherModel
    @ObservedObject var watched: WatchedCities
    let motion: WeatherMotion
    let renderer: WeatherIconRenderer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var panelColorScheme

    private let source = URL(string: "https://open-meteo.com/")!
    private let airSource = URL(string: "https://open-meteo.com/en/docs/air-quality-api")!
    private var showsSettings: Bool { model.showsSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if showsSettings {
                settings
            } else if model.showsWatchedCitySearch {
                watchedCitySearch
            } else if model.showsMotionPreview {
                WeatherMotionPreview(model: model, motion: motion, renderer: renderer)
            } else {
                if model.panelPage == .local {
                    conditions
                } else {
                    watchedSummary
                }
                pageSelector
            }
        }
        .padding(16)
        .frame(width: 348)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, Locale(identifier: "zh-Hans-CN"))
    }

    private var header: some View {
        let weather = model.showsWeatherDetails
        let local = model.showsLocalWeather
        let watchedPage = model.showsWatchedWeather
        let title = showsSettings ? "设置" : model.showsWatchedCitySearch ? "管理关注城市"
            : model.showsMotionPreview ? "天气动效预览"
            : watchedPage ? "关注城市"
            : (model.snapshot?.place.name ?? model.selectedCity ?? "当地天气")
        return HStack(spacing: 7) {
            Image(systemName: showsSettings ? "slider.horizontal.3"
                  : model.showsWatchedCitySearch || watchedPage ? "star"
                  : model.showsMotionPreview ? "play.circle" : "location.circle")
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if local {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 23, height: 23)
                }
                .buttonStyle(.plain)
                .help("刷新天气")
                .accessibilityLabel("刷新天气")
                .disabled([.loading, .locating, .noCity, .permission, .disabled].contains(model.notice))
            }
            if watchedPage {
                Button {
                    model.resetCitySearch()
                    model.showsWatchedCitySearch = true
                } label: {
                    Image(systemName: watched.places.isEmpty ? "plus" : "ellipsis.circle")
                        .frame(width: 23, height: 23)
                }
                .buttonStyle(.plain)
                .help(watched.places.isEmpty ? "添加城市" : "管理城市")
                .accessibilityLabel(watched.places.isEmpty ? "添加关注城市" : "管理关注城市")
            }
            Button {
                if weather {
                    model.resetCitySearch()
                    model.showsSettings = true
                } else if model.showsMotionPreview {
                    model.showsMotionPreview = false
                    model.showsSettings = true
                } else {
                    model.resetCitySearch()
                    model.showsSettings = false
                    model.showsWatchedCitySearch = false
                }
            } label: {
                Image(systemName: weather ? "gearshape" : "chevron.left")
                    .frame(width: 23, height: 23)
            }
            .buttonStyle(.plain)
            .help(weather ? "打开设置" : "返回天气")
            .accessibilityLabel(weather ? "打开设置" : "返回天气")
        }
    }

    private var pageSelector: some View {
        HStack(spacing: 14) {
            ForEach(WeatherPanelPage.allCases) { page in
                let active = model.panelPage == page
                Button {
                    model.panelPage = page
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(active ? Color.primary.opacity(0.76) : Color.secondary.opacity(0.25))
                            .frame(width: 5, height: 5)
                        Text(page.rawValue)
                            .font(.system(size: 10, weight: active ? .semibold : .regular))
                    }
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .padding(.horizontal, 7)
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = model.snapshot {
                hero(snapshot)
                if let note = statusMessage {
                    status(note, symbol: model.isStale || model.hasLastPlace ? "clock.arrow.circlepath" : "info.circle")
                }
                if !model.hasLastPlace, model.age < 2 * 3600 {
                    let hours = snapshot.nextHours(at: model.now)
                    if !hours.isEmpty { forecast(hours, from: snapshot) }
                    WeatherDetailsGrid(snapshot: snapshot, now: model.now)
                }
                HStack(spacing: 3) {
                    Text("天气时间 \(timeLabel(snapshot.validAt, in: snapshot, pattern: "M月d日 HH:mm"))")
                    Spacer(minLength: 5)
                    Link("Open-Meteo", destination: source)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("上次获取 \(timeLabel(snapshot.fetchedAt, in: snapshot, pattern: "M月d日 HH:mm"))（当地时间）")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cloud")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("暂无天气")
                        .font(.system(size: 17, weight: .semibold))
                    if let text = model.notice.text {
                        Text(text)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            }
            if model.notice == .permission || model.notice == .disabled || model.snapshot == nil {
                setupActions
            }
        }
    }

    private var statusMessage: String? {
        var parts: [String] = []
        if model.hasLastPlace {
            parts.append("显示上次地点的天气")
        }
        if model.isStale {
            parts.append("天气数据已过期")
        }
        if let text = model.notice.text {
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func airColor(_ category: AirQualityCategory) -> Color {
        switch category {
        case .good: Color(red: 0.20, green: 0.68, blue: 0.43)
        case .moderate: Color(red: 0.86, green: 0.66, blue: 0.13)
        case .sensitiveGroups: Color(red: 0.94, green: 0.49, blue: 0.18)
        case .unhealthy: Color(red: 0.84, green: 0.30, blue: 0.35)
        case .veryUnhealthy: Color(red: 0.62, green: 0.36, blue: 0.81)
        case .hazardous: Color(red: 0.55, green: 0.17, blue: 0.30)
        }
    }

    @ViewBuilder
    private func airQualityBadge(for snapshot: WeatherSnapshot) -> some View {
        if let reading = model.visibleAirQuality, let aqi = reading.aqi, let category = reading.category {
            let stale = reading.age(at: model.now) >= 2 * 3600
            let pm25 = reading.pm25.map {
                " · PM2.5 \($0.formatted(.number.precision(.fractionLength(0...1)))) μg/m³"
            } ?? ""
            VStack(alignment: .trailing, spacing: 2) {
                Text("AQI \(aqi)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                Text(stale ? "\(category.label) · 旧数据" : category.label)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.background.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("空气质量指数 \(aqi)，\(category.label)\(stale ? "，旧数据" : "")")
            .help("AQI · \(timeLabel(reading.validAt, in: snapshot, pattern: "M月d日 HH:mm"))\(pm25)")
        } else {
            Text(model.airQualityLoading ? "AQI 获取中" : model.airQualityUnavailable ? "AQI 暂不可用" : "AQI 暂缺")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var watchedSummary: some View {
        Group {
            if watched.places.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "star").font(.system(size: 24, weight: .light))
                    Text("还没有关注城市").font(.system(size: 13, weight: .medium))
                    Text("添加后可查看各城天气和未来三天预报。").font(.caption)
                        .foregroundStyle(.secondary)
                    Button("添加城市") {
                        model.resetCitySearch()
                        model.showsWatchedCitySearch = true
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 142)
                .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 11))
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(watched.places, id: \.self) { place in
                            watchedRow(place)
                        }
                    }
                }
                .frame(height: min(408, CGFloat(watched.places.count) * 103 - 7))
            }
        }
    }

    private func watchedRow(_ place: WeatherPlace) -> some View {
        let state = watched.state(for: place)
        let snapshot = state.snapshot.flatMap { $0.age(at: model.now) < 2 * 3600 ? $0 : nil }
        let daylight = snapshot?.isDay(at: model.now)
        let air = watched.airQuality(for: place).flatMap { $0.age(at: model.now) < 6 * 3600 ? $0 : nil }
        let oldAir = (air?.age(at: model.now) ?? .infinity) >= 2 * 3600
        let tint = oldAir ? nil : air?.category.map(airColor)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).lineLimit(1)
                HStack(spacing: 6) {
                    if let daylight {
                        Label(daylight ? "白天" : "夜间", systemImage: daylight ? "sun.max" : "moon.stars")
                            .labelStyle(.titleAndIcon)
                    }
                    if let aqi = air?.aqi {
                        Text(oldAir ? "AQI \(aqi) · 旧" : "AQI \(aqi)")
                            .monospacedDigit()
                            .accessibilityLabel("空气质量指数 \(aqi)\(oldAir ? "，旧数据" : "")")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let snapshot {
                let kind = WeatherKind(code: snapshot.code)
                ForecastWeatherIcon(code: snapshot.code, daylight: daylight, size: 18)
                    .accessibilityLabel(kind.label)
                if snapshot.age(at: model.now) >= 30 * 60 {
                    Image(systemName: "clock").help("显示上次天气").accessibilityLabel("上次数据")
                }
                let range = snapshot.highLow(at: model.now)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(temperatureText(snapshot.temperature))
                        .font(.system(size: 13, weight: .semibold))
                    if range.high != nil || range.low != nil {
                        Text("高 \(temperatureText(range.high)) · 低 \(temperatureText(range.low))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("最高 \(temperatureText(range.high))，最低 \(temperatureText(range.low))")
                    }
                }
                .monospacedDigit()
                .frame(minWidth: 60, alignment: .trailing)
            } else {
                Text(state.isLoading ? "获取中" : "—").foregroundStyle(.secondary)
            }
            }
            .frame(minHeight: 33)
            if let snapshot {
                let days = snapshot.nextDays(at: model.now)
                if !days.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(days, id: \.localDate) { day in
                            watchedDay(day, in: snapshot)
                        }
                    }
                } else {
                    Text("未来几天的预报暂缺").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text(state.isLoading ? "正在加载未来三天预报" : "未来几天的预报暂缺")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(8)
        .frame(minHeight: 96, alignment: .topLeading)
        .background {
            WeatherSky(code: snapshot?.code, daylight: daylight, airTint: tint, compact: true)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
        .environment(\.colorScheme, skyColorScheme(daylight))
    }

    private func watchedDay(_ day: WeatherDay, in snapshot: WeatherSnapshot) -> some View {
        let date = day.date(in: snapshot.locationTimeZone)
        let title = date.map { timeLabel($0, in: snapshot, pattern: "M/d") } ?? "—"
        let kind = WeatherKind(code: day.weatherCode)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                if day.weatherCode != nil {
                    ForecastWeatherIcon(code: day.weatherCode, daylight: true, size: 12)
                }
                Text(title).monospacedDigit()
                Text(day.weatherCode == nil ? "—" : kind.label).lineLimit(1)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            Text("\(temperatureText(day.high)) / \(temperatureText(day.low))")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
            WeatherTemperaturePalette.range(low: day.low, high: day.high)
                .frame(height: 2)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.32), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(kind.label)，最高 \(temperatureText(day.high))，最低 \(temperatureText(day.low))")
    }

    private var watchedCitySearch: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("关注城市单独显示，菜单栏仍显示当前主城市。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !watched.places.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(watched.places, id: \.self) { place in
                            HStack {
                                Text(place.name).font(.system(size: 12))
                                Spacer()
                                Button {
                                    watched.remove(place)
                                } label: {
                                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("取消关注\(place.name)")
                            }
                            .frame(height: 20)
                        }
                    }
                }
                .frame(height: min(5, CGFloat(watched.places.count)) * 24)
                Divider()
            }
            if watched.isFull {
                Text("已关注 8 个城市。移除一个后可继续添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                citySearch { city in
                    switch watched.add(city) {
                    case .added:
                        model.resetCitySearch()
                        model.showsWatchedCitySearch = false
                    case .alreadyWatched: model.setCityMessage("已经关注这个城市")
                    case .limitReached: model.setCityMessage("最多关注 8 个城市")
                    case .invalidCity: model.setCityMessage("这个地点不可用")
                    }
                }
            }
        }
    }

    private func hero(_ snapshot: WeatherSnapshot) -> some View {
        let profile = WeatherSceneProfile(code: snapshot.code, intensity: snapshot.intensity,
                                          windSpeed: snapshot.details?.windSpeed, gust: snapshot.gust,
                                          windDirection: snapshot.details?.windDirection)
        let daylight = snapshot.isDay(at: model.now)
        let daylightProgress = snapshot.daylightProgress(at: model.now)
        let mixed = snapshot.hasMixedPrecipitation
        let canShowToday = !model.hasLastPlace && model.age < 2 * 3600
        let range = snapshot.highLow(at: model.now)
        let reading = model.visibleAirQuality
        let category = reading.flatMap { $0.age(at: model.now) < 2 * 3600 ? $0.category : nil }
        let tint = category.map(airColor)
        return VStack(spacing: 10) {
            VStack(spacing: 2) {
                HStack(spacing: 9) {
                    CurrentWeatherIcon(motion: motion, renderer: renderer,
                                       code: mixed ? 66 : snapshot.code, daylight: daylight, intensity: snapshot.intensity,
                                       size: 42, gust: snapshot.gust)
                        .accessibilityLabel(mixed ? "雨雪混合" : profile.label)
                    Text(temperatureText(snapshot.temperature))
                        .font(.system(size: 52, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("摄氏 \(temperatureText(snapshot.temperature))")
                }
                HStack(spacing: 6) {
                    Text(mixed ? "雨雪混合" : profile.label)
                        .font(.system(size: 13, weight: .medium))
                    if let daylight {
                        Label(daylight ? "白天" : "夜间", systemImage: daylight ? "sun.max" : "moon.stars")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    if canShowToday && (range.high != nil || range.low != nil) {
                        Text("最高 \(temperatureText(range.high))  最低 \(temperatureText(range.low))")
                    }
                    if canShowToday, let wind = profile.wind, wind >= .moderate {
                        if let gust = snapshot.gust, gust >= 40 {
                            Text("阵风 \(gust.formatted(.number.precision(.fractionLength(0)))) km/h")
                        } else if let speed = snapshot.details?.windSpeed {
                            Text("风速 \(speed.formatted(.number.precision(.fractionLength(0)))) km/h")
                        }
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                airQualityBadge(for: snapshot)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                WeatherSky(code: snapshot.code, daylight: daylight, airTint: nil,
                           daylightProgress: daylightProgress)
                    .accessibilityHidden(true)
                WeatherScene(motion: motion, code: daylight == nil ? -1 : snapshot.code, isDay: daylight,
                             intensity: snapshot.intensity, gust: snapshot.gust,
                             windSpeed: snapshot.details?.windSpeed, windDirection: snapshot.details?.windDirection,
                             daylightProgress: daylightProgress,
                             special: mixed && daylight != nil ? .mixedPrecipitation : nil)
                    .accessibilityHidden(true)
                if let tint { WeatherAQIOverlay(tint: tint, daylight: daylight, localized: true) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        )
        .environment(\.colorScheme, skyColorScheme(daylight))
    }

    private func skyColorScheme(_ daylight: Bool?) -> ColorScheme {
        daylight.map { $0 ? .light : .dark } ?? panelColorScheme
    }

    private func forecast(_ hours: [WeatherHour], from snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("未来几小时")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(hours) { hour in
                    let kind = WeatherKind(code: hour.code)
                    let daylight = hour.daylight ?? snapshot.isDay(at: hour.time)
                    let clock = timeLabel(hour.time, in: snapshot, pattern: "HH:mm")
                    VStack(spacing: 6) {
                        Text(clock)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        ForecastWeatherIcon(code: hour.code, daylight: daylight, size: 18)
                            .frame(height: 20)
                        Text(temperatureText(hour.temperature))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(WeatherTemperaturePalette.color(for: hour.temperature).opacity(0.25),
                                        in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(clock)，\(kind.label)，\(temperatureText(hour.temperature))")
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 11))
    }

    private func status(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var setupActions: some View {
        HStack {
            if model.notice == .permission {
                Button("允许定位") { model.allowLocation() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
            if model.notice == .disabled {
                Button("打开定位设置") { model.openLocationSettings() }
                    .controlSize(.small)
            }
            Button("选择城市") {
                model.setMode(.manual)
                model.showsSettings = true
            }
            .controlSize(.small)
            Spacer()
            if model.snapshot == nil {
                Link("Open-Meteo", destination: source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("位置", selection: Binding(get: { model.mode }, set: model.setMode)) {
                ForEach(LocationMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if model.mode == .manual {
                manualSearch
            } else {
                Text("使用 macOS 定位，随所在城市更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Toggle("天气动画", isOn: Binding(get: { model.animationEnabled }, set: model.setAnimation))
                .toggleStyle(.switch)
                .controlSize(.small)
            if reduceMotion {
                Text("系统的「减少动态效果」已暂停动画。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.lowPowerMode {
                Text("系统低电量模式已暂停动画。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("面板外观", selection: Binding(get: { model.appearance }, set: model.setAppearance)) {
                ForEach(MenuAppearance.allCases) { Text($0.label).tag($0) }
            }
            .controlSize(.small)
            Toggle("登录时启动", isOn: Binding(get: { model.opensAtLogin }, set: { enabled in
                if enabled && model.loginItemNeedsApproval {
                    model.openLoginItemSettings()
                } else {
                    model.setOpensAtLogin(enabled)
                }
            }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!model.canSetLoginItem)
            if !model.canSetLoginItem {
                Text("将应用放入「应用程序」后，可设置登录启动。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.loginItemNeedsApproval || model.loginItemMessage != nil {
                Text(model.loginItemMessage ?? "请在系统设置中允许天气菜单栏在登录时打开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("打开登录项设置") { model.openLoginItemSettings() }
                    .controlSize(.small)
            }
            Button {
                model.showsSettings = false
                model.showsMotionPreview = true
            } label: {
                Label("查看天气动效", systemImage: "play.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            Divider()
            Text("天空背景随当地天气和昼夜变化，半透明色层表示 AQI 等级。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("天气数据来源", destination: source)
                Link("空气质量说明", destination: airSource)
                    .help("美国 AQI · CAMS / Open-Meteo，模型数据")
                Spacer()
                Button("退出天气菜单栏") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            Link("图标 · weather-iconic", destination: URL(string: "https://github.com/konradmichalik/weather-iconic")!)
                .font(.caption2)
                .help("Konrad Michalik · CC BY-SA 3.0 US")
        }
        .onAppear(perform: model.refreshLoginItemStatus)
    }

    private var manualSearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = model.selectedCity {
                Label(name, systemImage: "mappin.circle")
                    .font(.caption)
            }
            citySearch { city in
                model.chooseCity(city)
                model.resetCitySearch()
                model.showsSettings = false
            }
        }
    }

    private func citySearch(_ select: @escaping (CityChoice) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("城市名，例如南京", text: $model.cityQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.searchCities(model.cityQuery) }
                Button("搜索") { model.searchCities(model.cityQuery) }
                    .disabled(model.searching || model.cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.searching {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("正在搜索").font(.caption)
                }
            }
            if let message = model.cityMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if !model.cityResults.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.cityResults) { city in
                            Button {
                                select(city)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(city.name).font(.system(size: 12, weight: .medium))
                                        if !city.region.isEmpty {
                                            Text(city.region).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: min(130, CGFloat(model.cityResults.count * 38)))
            }
        }
    }

    private func timeLabel(_ date: Date, in snapshot: WeatherSnapshot, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = snapshot.locationTimeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

struct CurrentWeatherIcon: View {
    @ObservedObject var motion: WeatherMotion
    @Environment(\.colorScheme) private var colorScheme
    let renderer: WeatherIconRenderer
    let code: Int
    let daylight: Bool?
    let intensity: Double
    var size: CGFloat = 52
    var gust: Double?
    var cycloneDemo = false

    var body: some View {
        let upstream = TempsWeatherGlyph.image(code: code, isDay: daylight, size: size,
                                               cycloneDemo: cycloneDemo, phase: size == 18 ? motion.frame.menu : 0)
        let image = upstream ?? renderer.image(code: code, isDay: daylight, intensity: intensity,
                                               phase: size == 18 ? motion.frame.menu : motion.phase,
                                               dark: colorScheme == .dark, size: size,
                                               gust: gust, cycloneDemo: cycloneDemo, template: size == 18)
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .foregroundStyle(Color.primary.opacity(size == 18 ? 1 : 0.75))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct ForecastWeatherIcon: View {
    let code: Int?
    let daylight: Bool?
    let size: CGFloat

    var body: some View {
        Group {
            if let glyph = TempsWeatherGlyph.image(code: code, isDay: daylight, size: size) {
                Image(nsImage: glyph).renderingMode(.template)
            } else {
                Image(systemName: WeatherKind(code: code).symbolName(isDay: daylight))
                    .font(.system(size: size * 0.76))
            }
        }
        .foregroundStyle(Color.primary.opacity(0.78))
        .frame(width: size, height: size)
    }
}
