import SwiftUI

@MainActor
private final class WatchedCityExpansion: ObservableObject {
    @Published var place: WeatherPlace?
    @Published var pageIndex = 0
    @Published var rowHeights: [WeatherPlace: CGFloat] = [:]
    @Published var pageHeight: CGFloat = 0
    @Published var detailNaturalHeight: CGFloat = 0
    @Published var headerHeight: CGFloat = 23
    @Published var footerHeight: CGFloat = 24
}

struct WeatherPanel: View {
    @ObservedObject var model: WeatherModel
    @ObservedObject var watched: WatchedCities
    let motion: WeatherMotion
    let renderer: WeatherIconRenderer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var panelColorScheme
    @Environment(\.weatherPanelMaximumHeight) private var maximumHeight
    @StateObject private var watchedExpansion = WatchedCityExpansion()

    private let source = URL(string: "https://open-meteo.com/")!
    private let airSource = URL(string: "https://open-meteo.com/en/docs/air-quality-api")!
    private let panelPadding: CGFloat = 16
    private let panelSpacing: CGFloat = 14
    private var showsSettings: Bool { model.showsSettings }

    private var watchedChromeHeight: CGFloat {
        watchedExpansion.headerHeight + watchedExpansion.footerHeight + panelPadding * 2 + panelSpacing * 2
    }

    private var watchedBodyBudget: CGFloat? {
        maximumHeight.flatMap { $0.isFinite ? max(1, $0 - watchedChromeHeight) : nil }
    }

    private var watchedPages: [Range<Int>] {
        watchedCityPageRanges(rowHeights: watched.places.map { watchedExpansion.rowHeights[$0] ?? 96 },
                             availableHeight: watchedBodyBudget.map { max(0, $0 - 2) })
    }

    private var watchedPageIndex: Int {
        min(max(0, watchedExpansion.pageIndex), max(0, watchedPages.count - 1))
    }

    private var immersiveSnapshot: WeatherSnapshot? {
        if model.showsMotionPreview {
            return model.previewWeather.snapshot(at: model.previewWeather.sceneDate(relativeTo: model.now))
        }
        if model.showsWatchedWeather, let place = watched.selectedPlace {
            return watched.state(for: place).snapshot.flatMap { $0.age(at: model.now) < 2 * 3600 ? $0 : nil }
        }
        guard model.showsLocalWeather, !model.hasLastPlace, model.age < 2 * 3600 else { return nil }
        return model.snapshot
    }

    private var skyTime: Date {
        if model.showsMotionPreview { return model.previewWeather.sceneDate(relativeTo: model.now) }
        return model.now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: panelSpacing) {
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
        .padding(panelPadding)
        .frame(width: 348)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if let snapshot = immersiveSnapshot {
                ZStack {
                    Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                    ImmersiveWeatherBackdrop(motion: motion, snapshot: snapshot, now: skyTime,
                                             special: model.showsMotionPreview ? model.previewWeather.special : nil,
                                             cycloneDemo: model.showsMotionPreview && model.previewWeather == .typhoon)
                        .opacity(0.92)
                }
            } else if model.showsWatchedWeather {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .overlayPreferenceValue(WeatherCardBoundsKey.self) { anchors in
            if let snapshot = immersiveSnapshot {
                GeometryReader { geometry in
                    WeatherCardRainOverlay(motion: motion, snapshot: snapshot,
                                           surfaces: model.showsWatchedWeather ? [] : anchors.map { geometry[$0] })
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .environment(\.immersiveWeather, immersiveSnapshot != nil)
        .environment(\.colorScheme, immersiveSnapshot == nil ? panelColorScheme : .dark)
        .environment(\.locale, Locale(identifier: "zh-Hans-CN"))
        .preference(key: WatchedWeatherNaturalHeightKey.self,
                    value: model.showsWatchedWeather ? watchedChromeHeight + watchedExpansion.pageHeight : 0)
        .onChange(of: watched.places) { _, places in
            if let expanded = watchedExpansion.place, !places.contains(expanded) {
                watchedExpansion.place = nil
            }
            watchedExpansion.rowHeights = watchedExpansion.rowHeights.filter { places.contains($0.key) }
            watchedExpansion.pageIndex = watchedPageIndex
        }
        .onChange(of: watchedPages) { _, _ in watchedExpansion.pageIndex = watchedPageIndex }
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
                .help(title)
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
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { watchedExpansion.headerHeight = $0 }
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
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { watchedExpansion.footerHeight = $0 }
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = model.snapshot {
                hero(snapshot)
                if let note = statusMessage {
                    status(note, symbol: model.isStale || model.hasLastPlace ? "clock.arrow.circlepath" : "info.circle")
                }
                if !model.hasLastPlace, model.age < 2 * 3600 {
                    AirQualityIndexLine(reading: model.visibleAirQuality, now: model.now,
                                        isLoading: model.airQualityLoading, isUnavailable: model.airQualityUnavailable,
                                        history: model.visibleAirQualityHistory)
                    PrecipitationTrendCard(snapshot: snapshot, now: model.now)
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

    private var watchedSummary: some View {
        Group {
            if let place = watchedExpansion.place, watched.places.contains(place) {
                watchedDetailPage(place)
            } else if watched.places.isEmpty {
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
                watchedListPage
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
            watchedExpansion.pageHeight = $0
        }
        .background(alignment: .top) {
            // At most eight cards: measure every row at its actual width even
            // when pagination hides it. This layer never receives input or AX.
            VStack(spacing: 8) {
                ForEach(watched.places, id: \.self) { place in
                    watchedRow(place)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                            guard height.isFinite, height > 0,
                                  watchedExpansion.rowHeights[place] != height else { return }
                            watchedExpansion.rowHeights[place] = height
                        }
                }
            }
            .padding(1)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var watchedListPage: some View {
        let pages = watchedPages
        let index = watchedPageIndex
        let range = pages.isEmpty ? 0..<0 : pages[index]
        let places = Array(watched.places[range])
        let naturalHeight = places.reduce(CGFloat(0)) { $0 + (watchedExpansion.rowHeights[$1] ?? 96) }
            + CGFloat(max(0, places.count - 1)) * 8
        let controlsHeight: CGFloat = pages.count > 1 ? 32 : 0
        let budget = watchedBodyBudget.map { max(1, $0 - controlsHeight - 2) }
        let scale = min(1, (budget ?? naturalHeight) / max(1, naturalHeight))
        return VStack(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(places, id: \.self) { place in
                    watchedCityButton(place)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(scale, anchor: .top)
            .frame(height: naturalHeight * scale, alignment: .top)
            if pages.count > 1 {
                HStack {
                    Button { watchedExpansion.pageIndex = index - 1 } label: {
                        Label("上一页", systemImage: "chevron.left")
                    }
                    .disabled(index == 0)
                    Spacer()
                    Text("\(index + 1) / \(pages.count)")
                        .monospacedDigit()
                        .accessibilityLabel("第 \(index + 1) 页，共 \(pages.count) 页")
                    Spacer()
                    Button { watchedExpansion.pageIndex = index + 1 } label: {
                        Label("下一页", systemImage: "chevron.right")
                    }
                    .disabled(index == pages.count - 1)
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .frame(height: 24)
            }
        }
        .padding(1)
    }

    private func watchedDetailPage(_ place: WeatherPlace) -> some View {
        let naturalHeight = watchedExpansion.detailNaturalHeight
        let scale = min(1, (watchedBodyBudget ?? naturalHeight) / max(1, naturalHeight))
        return VStack(spacing: 10) {
            watchedCityButton(place, compact: true)
            watchedDetails(place)
        }
        .padding(1)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
            watchedExpansion.detailNaturalHeight = $0
        }
        // Only unusually short screens need this uniform fit. No card or
        // detail is clipped, and the normal menu uses its unscaled size.
        .scaleEffect(naturalHeight > 0 ? scale : 1, anchor: .top)
        .frame(height: naturalHeight > 0 ? naturalHeight * scale : nil, alignment: .top)
    }

    private func watchedCityButton(_ place: WeatherPlace, compact: Bool = false) -> some View {
        Button {
            toggleWatchedCity(place)
        } label: {
            watchedRow(place, compact: compact)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(place.name)，\(watchedExpansion.place == place ? "返回城市列表" : "展开天气详情")")
        .accessibilityAddTraits(watched.selectedPlace == place ? .isSelected : [])
    }

    private func toggleWatchedCity(_ place: WeatherPlace) {
        watched.select(place)
        watchedExpansion.place = watchedExpansion.place == place ? nil : place
    }

    @ViewBuilder
    private func watchedDetails(_ place: WeatherPlace) -> some View {
        let state = watched.state(for: place)
        if let snapshot = state.snapshot, snapshot.age(at: model.now) < 2 * 3600 {
            VStack(alignment: .leading, spacing: 10) {
                let hours = snapshot.nextHours(at: model.now)
                if !hours.isEmpty { forecast(hours, from: snapshot) }
                WeatherDetailsGrid(snapshot: snapshot, now: model.now)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 6)
        } else {
            Text(state.isLoading ? "正在获取天气详情" : "天气详情暂不可用")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
                .weatherGlassCard()
        }
    }

    private func watchedRow(_ place: WeatherPlace, compact: Bool = false) -> some View {
        let state = watched.state(for: place)
        let snapshot = state.snapshot.flatMap { $0.age(at: model.now) < 2 * 3600 ? $0 : nil }
        let daylight = snapshot?.isDay(at: model.now)
        let air = watched.airQuality(for: place).flatMap { $0.age(at: model.now) < 6 * 3600 ? $0 : nil }
        let oldAir = (air?.age(at: model.now) ?? .infinity) >= 2 * 3600
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if watched.selectedPlace == place {
                        Circle().fill(.white).frame(width: 4, height: 4)
                            .accessibilityHidden(true)
                    }
                    Text(place.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(place.name)
                    if let snapshot {
                        let kind = WeatherKind(code: snapshot.code)
                        ForecastWeatherIcon(code: snapshot.code, daylight: daylight, size: 18)
                            .accessibilityLabel(kind.label)
                            .fixedSize()
                        Text(temperatureText(snapshot.temperature))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                        let range = snapshot.highLow(at: model.now)
                        if range.high != nil || range.low != nil {
                            Text("高 \(temperatureText(range.high)) · 低 \(temperatureText(range.low))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .fixedSize(horizontal: true, vertical: false)
                                .accessibilityLabel("最高 \(temperatureText(range.high))，最低 \(temperatureText(range.low))")
                        }
                    } else {
                        Text(state.isLoading ? "获取中" : "—")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: watchedExpansion.place == place ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
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
                    if let snapshot, snapshot.age(at: model.now) >= 30 * 60 {
                        Image(systemName: "clock").help("显示上次天气").accessibilityLabel("上次数据")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
            .frame(minHeight: 33)
            if !compact {
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
        }
        .font(.system(size: 12))
        .padding(8)
        .frame(minHeight: compact ? 49 : 96, alignment: .topLeading)
        .weatherGlassCard(cornerRadius: 10)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(watched.selectedPlace == place ? 0.48 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
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
        let mixed = snapshot.hasMixedPrecipitation
        let canShowToday = !model.hasLastPlace && model.age < 2 * 3600
        let range = snapshot.highLow(at: model.now)
        return VStack(spacing: 6) {
            Text(temperatureText(snapshot.temperature))
                .font(.system(size: 68, weight: .thin, design: .rounded))
                .monospacedDigit()
                .shadow(color: .black.opacity(0.12), radius: 7, y: 2)
                .accessibilityLabel("摄氏 \(temperatureText(snapshot.temperature))")
            HStack(spacing: 6) {
                CurrentWeatherIcon(motion: motion, renderer: renderer,
                                   code: mixed ? 66 : snapshot.code, daylight: daylight,
                                   intensity: snapshot.intensity, size: 20, gust: snapshot.gust)
                    .accessibilityHidden(true)
                Text(mixed ? "雨雪混合" : profile.label)
                    .font(.system(size: 13, weight: .medium))
            }
            HStack(spacing: 12) {
                if canShowToday && (range.high != nil || range.low != nil) {
                    Text("最高 \(temperatureText(range.high))  最低 \(temperatureText(range.low))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if canShowToday, let wind = profile.wind, wind >= .moderate {
                if let gust = snapshot.gust, gust >= 40 {
                    Text("阵风 \(gust.formatted(.number.precision(.fractionLength(0)))) km/h")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else if let speed = snapshot.details?.windSpeed {
                    Text("风速 \(speed.formatted(.number.precision(.fractionLength(0)))) km/h")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 13)
    }

    private func forecast(_ hours: [WeatherHour], from snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("未来几小时")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Label("降水概率", systemImage: "drop")
                    .font(.system(size: 9))
            }
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
                        Text(probabilityText(hour.rainProbability))
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle((hour.rainProbability ?? 0) > 0
                                ? precipitationAccent : Color.secondary)
                            .help("\(PrecipitationTrend.intervalLabel(for: hour, relativeTo: model.now, in: snapshot.locationTimeZone))降水概率：\(probabilityText(hour.rainProbability))")
                        Text(temperatureText(hour.temperature))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(WeatherTemperaturePalette.color(for: hour.temperature).opacity(0.25),
                                        in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(clock)，\(kind.label)，\(temperatureText(hour.temperature))，\(PrecipitationTrend.intervalLabel(for: hour, relativeTo: model.now, in: snapshot.locationTimeZone))降水概率\(probabilityText(hour.rainProbability))")
                }
            }
        }
        .padding(10)
        .weatherGlassCard()
    }

    private var precipitationAccent: Color {
        immersiveSnapshot != nil || panelColorScheme == .dark ? Color(red: 0.38, green: 0.77, blue: 0.96)
            : Color(red: 0.08, green: 0.40, blue: 0.65)
    }

    private func probabilityText(_ value: Double?) -> String {
        guard let value, value.isFinite, (0...100).contains(value) else { return "—" }
        return "\(Int(value.rounded()))%"
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
            Text("天空背景随当地天气和昼夜变化，AQI 以渐变色带和数值显示。")
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
            Link("天空背景 · Created with Grok（AI 生成）", destination: URL(string: "https://x.ai")!)
                .font(.caption2)
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

struct ForecastWeatherIcon: View {
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
