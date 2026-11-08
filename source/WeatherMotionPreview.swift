import SwiftUI

private enum WeatherDemoGroup: String, CaseIterable, Identifiable {
    case sky = "天空与能见度"
    case rain = "液态降水"
    case winter = "冰雪天气"
    case severe = "风与雷电"

    var id: Self { self }
}

enum WeatherDemo: String, CaseIterable, Identifiable {
    case sun = "晴天"
    case dawn = "清晨晴空"
    case dusk = "傍晚晴空"
    case moon = "晴夜"
    case mostlyClear = "少云"
    case partlyCloudy = "晴间多云"
    case overcast = "阴天"
    case overcastNight = "阴夜"
    case fog = "雾"
    case freezingFog = "雾伴霜"
    case haze = "霾（模拟）"
    case drizzle = "毛毛雨"
    case lightRain = "小雨"
    case rain = "中雨"
    case heavyRain = "大雨"
    case lightShowers = "小阵雨"
    case showers = "强阵雨"
    case freezingDrizzle = "冻毛毛雨"
    case freezingRain = "冻雨"
    case mixed = "雨夹雪（模拟）"
    case snow = "雪"
    case heavySnow = "大雪"
    case snowGrains = "雪粒"
    case snowShowers = "阵雪"
    case blowingSnow = "强风大雪"
    case thunder = "雷雨"
    case heavyThunder = "强雷雨"
    case lightHail = "雷雨伴小冰雹"
    case hail = "雷雨伴冰雹"
    case wind = "大风"
    case typhoon = "台风场景"

    var id: Self { self }
    fileprivate var group: WeatherDemoGroup {
        switch self {
        case .sun, .dawn, .dusk, .moon, .mostlyClear, .partlyCloudy, .overcast,
             .overcastNight, .fog, .freezingFog, .haze: .sky
        case .drizzle, .lightRain, .rain, .heavyRain, .lightShowers, .showers: .rain
        case .freezingDrizzle, .freezingRain, .mixed, .snow, .heavySnow, .snowGrains,
             .snowShowers, .blowingSnow: .winter
        case .thunder, .heavyThunder, .lightHail, .hail, .wind, .typhoon: .severe
        }
    }

    var code: Int {
        switch self {
        case .sun, .dawn, .dusk, .moon: 0
        case .mostlyClear: 1
        case .partlyCloudy, .wind: 2
        case .overcast, .overcastNight: 3
        case .fog, .haze: 45
        case .freezingFog: 48
        case .drizzle: 53
        case .lightRain: 61
        case .rain, .mixed: 63
        case .heavyRain, .typhoon: 65
        case .lightShowers: 80
        case .showers: 82
        case .freezingDrizzle: 56
        case .freezingRain: 67
        case .snow: 73
        case .heavySnow, .blowingSnow: 75
        case .snowGrains: 77
        case .snowShowers: 85
        case .thunder: 95
        case .heavyThunder: 97
        case .lightHail: 96
        case .hail: 99
        }
    }

    var iconCode: Int { self == .mixed ? 66 : code }

    var special: WeatherSceneSpecial? {
        switch self {
        case .haze: .haze
        case .mixed: .mixedPrecipitation
        default: nil
        }
    }

    var intensity: Double {
        switch self {
        case .drizzle, .freezingDrizzle, .snowGrains: 0.4
        case .lightRain, .lightShowers: 0.8
        case .lightHail: 3
        case .rain, .freezingRain, .mixed: 3
        case .thunder: 4
        case .heavyRain, .showers, .typhoon, .heavyThunder, .hail: 9
        case .snow, .snowShowers: 2
        case .heavySnow, .blowingSnow: 5
        default: 0
        }
    }

    var gust: Double? {
        switch self {
        case .typhoon: 110
        case .wind: 60
        case .blowingSnow: 65
        case .heavyThunder: 60
        case .thunder, .heavyRain, .showers, .lightHail, .hail: 45
        default: nil
        }
    }

    var windSpeed: Double? {
        switch self {
        case .wind: 36
        case .blowingSnow: 45
        default: nil
        }
    }

    var windDirection: Double? {
        switch self {
        case .wind, .heavyRain, .blowingSnow: 270
        case .showers, .thunder, .heavyThunder, .lightHail, .hail: 120
        default: nil
        }
    }

    var isDay: Bool {
        switch self {
        case .moon, .overcastNight, .thunder, .heavyThunder, .lightHail, .hail, .typhoon: false
        default: true
        }
    }

    var daylightProgress: Double? {
        guard isDay else { return nil }
        switch self {
        case .dawn: return 0.04
        case .dusk: return 0.96
        default: return 0.48
        }
    }

    /// Explicit gallery clock: real Shanghai daytime/nighttime on the selected
    /// calendar date, with dawn/dusk derived from actual solar horizon events.
    @MainActor
    func sceneDate(relativeTo now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let daytime = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: now)!
        if self == .dawn || self == .dusk {
            let events = NightSkyAstronomy.sunEvents(dayStartingAt: calendar.startOfDay(for: now),
                                                     coordinate: .init(latitude: 31.2, longitude: 121.5))
            if self == .dawn, let sunrise = events.sunrise { return sunrise + 20 * 60 }
            if self == .dusk, let sunset = events.sunset { return sunset - 20 * 60 }
        }
        return isDay ? daytime : calendar.date(bySettingHour: 21, minute: 30, second: 0, of: now)!
    }

    /// Synthetic weather at the supplied absolute instant. Solar metadata uses
    /// that instant and place; it never forces daytime by fabricating sun times.
    @MainActor
    func snapshot(at now: Date, place: WeatherPlace? = nil) -> WeatherSnapshot {
        let place = place ?? WeatherPlace(name: "模拟场景", coordinate: .init(latitude: 31.2, longitude: 121.5))
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let localDate = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
        let events = NightSkyAstronomy.sunEvents(dayStartingAt: calendar.startOfDay(for: now), coordinate: place.coordinate)
        let daylight = NightSkyAstronomy.sky(at: now, coordinate: place.coordinate).map { $0.sun.altitudeDegrees >= 0 }
        let temperature: Double
        switch self {
        case .sun: temperature = 26
        case .dawn: temperature = 17
        case .dusk: temperature = 23
        case .moon, .overcastNight: temperature = 14
        case .freezingFog, .freezingDrizzle, .freezingRain, .mixed: temperature = -1
        case .snow, .heavySnow, .snowGrains, .snowShowers, .blowingSnow: temperature = -4
        default: temperature = 19
        }
        let firstHour = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 3600) + 1) * 3600)
        let amounts = [1.0, 0.65, 0.2, 0.05, 0, 0].map { $0 * intensity }
        let hours = amounts.enumerated().map { index, amount in
            let time = firstHour + Double(index) * 3600
            let hourIsDay = NightSkyAstronomy.sky(at: time, coordinate: place.coordinate).map { $0.sun.altitudeDegrees >= 0 }
            return WeatherHour(time: time,
                        temperature: temperature - Double(index / 2),
                        code: intensity == 0 || amount >= 0.1 ? code : 3,
                        daylight: hourIsDay, rainProbability: amount >= 0.1 ? 75 : intensity > 0 ? 15 : 5,
                        uvIndex: hourIsDay == true ? 2 : 0, precipitation: amount)
        }
        return WeatherSnapshot(
            place: place,
            temperature: temperature, code: code, intensity: intensity,
            validAt: now, fetchedAt: now, timezone: timeZone.identifier,
            utcOffsetSeconds: timeZone.secondsFromGMT(for: now), currentDaylight: daylight,
            hours: hours,
            days: [WeatherDay(localDate: localDate, high: temperature + 2, low: temperature - 4,
                              sunrise: events.sunrise, sunset: events.sunset, weatherCode: code)],
            gust: gust,
            details: WeatherCurrentDetails(feelsLike: temperature - 2, humidity: intensity > 0 ? 88 : 55,
                                           windSpeed: windSpeed ?? gust.map { $0 * 0.55 },
                                           windDirection: windDirection, pressure: 1012, dewPoint: temperature - 3),
            mixedPrecipitation: self == .mixed ? true : nil)
    }
}

struct WeatherMotionPreview: View {
    @ObservedObject var model: WeatherModel
    let motion: WeatherMotion
    let renderer: WeatherIconRenderer

    var body: some View {
        let sample = model.previewWeather
        let sceneDate = sample.sceneDate(relativeTo: model.now)
        let snapshot = sample.snapshot(at: sceneDate)
        let daylight = snapshot.isDay(at: sceneDate) ?? sample.isDay
        let cyclone = sample == .typhoon
        return VStack(alignment: .leading, spacing: 11) {
            Picker("模拟天气", selection: $model.previewWeather) {
                ForEach(WeatherDemoGroup.allCases) { group in
                    Section(group.rawValue) {
                        ForEach(WeatherDemo.allCases.filter { $0.group == group }) { weather in
                            Text(weather.rawValue).tag(weather)
                        }
                    }
                }
            }
            .controlSize(.small)

            VStack(spacing: 7) {
                Text("\(Int(snapshot.temperature.rounded()))°")
                    .font(.system(size: 65, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.15), radius: 7, y: 2)
                HStack(spacing: 7) {
                    CurrentWeatherIcon(motion: motion, renderer: renderer, code: sample.iconCode,
                                       daylight: daylight, intensity: sample.intensity, size: 23,
                                       gust: sample.gust, cycloneDemo: cyclone)
                        .accessibilityHidden(true)
                    Text(sample.rawValue).font(.system(size: 18, weight: .medium))
                }
                Text("模拟场景 · 非实时预报")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                Text("模拟时刻 · \(clockLabel(sceneDate, in: snapshot.locationTimeZone))（上海）")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 163)

            PrecipitationTrendCard(snapshot: snapshot, now: sceneDate)
            hourlySamples(snapshot)

            HStack(spacing: 8) {
                CurrentWeatherIcon(motion: motion, renderer: renderer, code: sample.iconCode,
                                   daylight: daylight, intensity: sample.intensity, size: 18,
                                   gust: sample.gust, cycloneDemo: cyclone)
                VStack(alignment: .leading, spacing: 3) {
                    Text("菜单栏图标预览").font(.system(size: 10, weight: .medium))
                    Text("此页天气与数值均为演示")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .weatherGlassCard()

            if cyclone {
                VStack(alignment: .leading, spacing: 3) {
                    Text("台风动效仅供模拟；当地预警以官方信息为准。")
                    Link("中央气象台台风网", destination: URL(string: "https://typhoon.nmc.cn/web.html")!)
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            } else if sample == .haze {
                Text("此场景仅供预览，实时天气没有独立识别。")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else if sample == .mixed {
                Text("实时画面在同一模型时段同时返回雨和雪时使用此效果。")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func hourlySamples(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("逐小时预报 · 演示数据")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(snapshot.hours) { hour in
                    VStack(spacing: 6) {
                        Text(clockLabel(hour.time, in: snapshot.locationTimeZone))
                            .font(.system(size: 10)).monospacedDigit()
                        ForecastWeatherIcon(code: hour.code, daylight: hour.daylight, size: 18)
                            .frame(height: 22)
                        Text("\(Int(hour.rainProbability ?? 0))%")
                            .font(.system(size: 10, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Color(red: 0.48, green: 0.81, blue: 1))
                        Text("\(Int((hour.temperature ?? 0).rounded()))°")
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .weatherGlassCard()
    }

    private func clockLabel(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
