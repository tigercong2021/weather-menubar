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
}

struct WeatherMotionPreview: View {
    @ObservedObject var model: WeatherModel
    let motion: WeatherMotion
    let renderer: WeatherIconRenderer

    var body: some View {
        let sample = model.previewWeather
        let isDay = sample.isDay
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

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(sample.rawValue).font(.system(size: 24, weight: .semibold))
                    Text("模拟场景").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                CurrentWeatherIcon(motion: motion, renderer: renderer, code: sample.iconCode,
                                   daylight: isDay, intensity: sample.intensity,
                                   gust: sample.gust, cycloneDemo: cyclone)
            }
            .padding(15)
            .frame(minHeight: 128)
            .background {
                ZStack {
                    WeatherSky(code: sample.code, daylight: isDay, airTint: nil,
                               daylightProgress: sample.daylightProgress)
                        .accessibilityHidden(true)
                    WeatherScene(motion: motion, code: sample.code, isDay: isDay,
                                 intensity: sample.intensity, gust: sample.gust, cycloneDemo: cyclone,
                                 windSpeed: sample.windSpeed, windDirection: sample.windDirection,
                                 daylightProgress: sample.daylightProgress, special: sample.special)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .environment(\.colorScheme, isDay ? .light : .dark)

            HStack(spacing: 8) {
                CurrentWeatherIcon(motion: motion, renderer: renderer, code: sample.iconCode,
                                   daylight: isDay, intensity: sample.intensity, size: 18,
                                   gust: sample.gust, cycloneDemo: cyclone)
                Text("菜单栏图标预览").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }

            if cyclone {
                Text("此处仅展示台风动效。当地预警请查阅官方气象信息。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Link("中央气象台台风网", destination: URL(string: "https://typhoon.nmc.cn/web.html")!)
                    .font(.caption2)
            } else if sample == .haze {
                Text("此场景仅供预览，实时天气没有独立识别。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if sample == .mixed {
                Text("实时画面在同一模型时段同时返回雨和雪时使用此效果。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
